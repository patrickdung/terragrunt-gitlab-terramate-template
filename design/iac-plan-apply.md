# Infrastructure as Code (IaC) Plan & Apply Template

The `iac-plan-apply.md` template implements the core deployment workflow for multi-stack environments orchestrated by Terramate.

## Purpose

- **Change Detection**: Uses `terramate list --changed` to find modified stacks.
- **Speculative Previews**: Generates "Advisory" plans for Merge Requests. The plan is for viewing only. Another plan for planning will be created after MR is merged.
- **Secure Plan Storage**: Utilize openssl to encrypt binary Terraform plans.
- **Manual Promotion**: Ensures `apply` operations are gated by manual triggers.
- **Reporting**: Generates human-readable summaries of infrastructure changes.
- **Dependency Ordering**: Plans and applies stacks in Terragrunt dependency (DAG) order via Terramate.

## Stack dependency ordering (DAG)

Stacks that depend on each other (e.g. stack C consumes outputs of stacks A
and B via Terragrunt `dependency` blocks) are planned and applied in
dependency order, not path order:

- **DAG source**: Terramate builds the dependency graph from Terragrunt
  `dependency` blocks found in each stack's **root** `terragrunt.hcl` — a
  proper root module with a `terraform { source = ... }` block. Dependency
  blocks in a shared include-only file (e.g. a `terragrunt-root.hcl` without
  a `terraform` block) are **not** detected by Terramate and do not create
  ordering edges.
- **Plan jobs** (`plan-mr-preview`, `plan-main`) run
  `terramate list --changed ${IAC_TERRAMATE_PLAN_EXTRA_FLAGS}` where the
  default flags are `--include-all-dependents --run-order`:
  - `--include-all-dependents` — if stack A changed, stack C (which depends
    on A) is also planned, because its inputs may change.
  - `--run-order` — the list is sorted in DAG execution order (dependencies
    first), so the per-stack plan loop processes A and B before C.
- **Apply job** iterates `plan-manifest.txt` in the order `plan-main` wrote
  it (DAG order). Before applying, it sanity-checks that the manifest order
  matches `terramate list --run-order` filtered to the manifest entries and
  warns (non-fatal) on mismatch.
- **Cycle detection**: both plan jobs run `terramate list --run-order` as a
  fail-fast check; a dependency cycle aborts the job with a clear error
  before any planning starts.
- **Toggle**: set `IAC_TERRAMATE_PLAN_EXTRA_FLAGS: ""` in a consumer repo to
  restore the old behaviour (changed stacks only, path order).

### Consumer requirements for dependent stacks

- New stacks that depend on not-yet-existing stacks **must** declare
  `mock_outputs` and `mock_outputs_allowed_terraform_commands` in their
  `dependency` blocks, otherwise `terragrunt plan` fails with "detected no
  outputs" when the upstream state does not exist yet:

  ```hcl
  dependency "vpc" {
    config_path = "../vpc"

    mock_outputs = {
      vpc_id = "vpc-00000000"   # obviously fake: an accidental apply-with-mocks fails loudly
    }
    mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
  }
  ```

  Real `apply` still demands real outputs — mocks only fill in for
  plan-like commands when the upstream has no state yet.
- **`"show"` must be in the allowed list.** This template's plan loop runs
  `terragrunt show -json <planfile>` immediately after `terragrunt plan
  -out <planfile>` for every stack (the show JSON feeds tf-summarize,
  tfplan2md, and iam-policy-autopilot). `show` re-resolves dependency
  outputs just like `plan` does, so with only `["init", "validate", "plan"]`
  the plan step succeeds with mocks but the very next `show` step fails
  with:

  ```
  ERROR  There is no variable named "dependency".
  ERROR  resolving dependency "a1" outputs: ... but detected no outputs.
  ```

  (Observed in a real pipeline: `plan` printed "Plan: 2 to add" using the
  mock ARN, then `show -json` errored one second later.) Verified fix:
  adding `"show"` to `mock_outputs_allowed_terraform_commands` makes both
  steps succeed with mocks on a fresh environment.
- Keep `dependency` blocks in each stack's root `terragrunt.hcl` (with a
  `terraform { source = ... }` block), not in a shared include-only file,
  so Terramate can detect them for ordering.

### First-time deploy of a dependency chain takes one pipeline run per link

The saved-plan apply is **incompatible with a dependency becoming real
mid-run**. `tofu apply <planfile>` re-renders the Terragrunt config (dependency
outputs are re-resolved at apply time) and then compares the rendered input
variables against the values baked into the plan file. If a dependency that
was unapplied at plan time (its dependent's plan therefore baked
`mock_outputs` values) gets applied **earlier in the same apply run**, the
dependent's re-rendered inputs now hold the dependency's real outputs and no
longer match the plan file. OpenTofu refuses:

```
Error: Mismatch between input and plan variable value
Value saved in the plan file for variable "policies" is different from the
one given to the current command.
```

This is OpenTofu's saved-plan safety check working as designed, and it is a
**structural property of this template's design** (plan once → apply the
saved plans), not a bug. Consequences and the accepted operating procedure:

- **First-time deploy of an N-stack chain takes N pipeline runs.** Each run
  advances the chain by one link: run k applies the k-th stack (its plan was
  regenerated against the now-real outputs of link k-1) and fails on link
  k+1 with the mismatch error above. Observed on the a1→a2→a3 dag-chain test:
  run 1 applied a1 / failed a2; run 2 applied a2 / failed a3; run 3 applied
  a3. Re-run the pipeline (do not retry the apply job — it re-uses the same
  stale saved plans) until the chain completes.
- **Subsequent runs are no-ops.** Once every stack in the chain has state,
  plans are made from real outputs everywhere and apply succeeds in one run.
- **Do not add `apply` to `mock_outputs_allowed_terraform_commands`** to work
  around this — that would let a dependent apply against mock values and
  create real resources wired to fake ARNs.
- **A failed dependency apply must re-enter the changed set.** Change
  detection is git-based: if a later MR only touches dependent stacks, the
  failed dependency is excluded from plan-main/apply-main and the chain
  stalls. Touch the dependency stack's config (a comment is enough) in the
  same MR so Terramate includes it; `--include-all-dependents` then pulls the
  dependents in and `--run-order` applies the dependency first.
- **Partial outputs after a failed apply also break plan-time** (a different
  failure mode): a failed apply still writes a state file, and input-derived
  outputs (e.g. a policy module's `name`/`policy`) are known before apply
  while resource-dependent outputs (`arn`) are not. A non-empty partial
  output fetch does **not** trigger Terragrunt's plain mock fallback (mocks
  are only used when outputs are missing entirely), so the dependent fails
  with `Unsupported attribute`. Fix: add
  `mock_outputs_merge_strategy_with_state = "shallow"` to the dependency
  block — missing keys are filled from `mock_outputs` while real state
  outputs are kept. Like all mock behavior it is gated by
  `mock_outputs_allowed_terraform_commands`, so it only affects plan-like
  commands, never apply.

## Key Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TF_STATE_ARTIFACT_ENCRYPTION_KEY` | Passphrase used to encrypt/decrypt binary Terraform plan files. For this variable in GitLab, please remember to set protected and masked | Undefined |
| `IAC_TERRAMATE_PLAN_EXTRA_FLAGS` | Extra flags for `terramate list --changed` in the plan jobs. Default `"--include-all-dependents --run-order"` (re-plan dependents of changed stacks; iterate in DAG execution order). Set to `""` to restore changed-stacks-only, path-order behaviour. | Optional (default provided) |
| `GITLAB_API_TOKEN` | Project or group access token (`api` scope, Maintainer/Owner role) used by `plan-mr-preview` to post the MR plan note, by `plan-main` to post the plan as a commit comment, and by `apply` to delete `plan-main` artifacts after a successful apply. If unset, note posting and artifact deletion are skipped (non-fatal). | Optional |
| `DISABLE_IAM_POLICY_AUTOPILOT_TELEMETRY` | Defaults to `"true"` — opts out of iam-policy-autopilot telemetry. Highest precedence (beats the tool's persisted `~/.iam-policy-autopilot/config.json` choice); `telemetry --disable` is also run best-effort in the plan job. | Optional (default provided) |
| `IAM_POLICY_AUTOPILOT_TO_MR_COMMIT` | Defaults to `"true"`. The generated IAM policies are always kept as `plan-mr-preview` artifacts; set to `"false"` to skip appending them to the MR plan note (large diffs -> huge MR comment). | Optional (default provided) |
| `IAM_POLICY_AUTOPILOT_APPEND_TO_JOB_LOG` | Defaults to `"true"`. The pretty JSON is also echoed to the `plan-mr-preview` job log (the job trace, not the MR comment); set to `"false"` to keep the log small on large diffs. | Optional (default provided) |
## IAM policy generation from the plan (MR preview only)

`plan-mr-preview` runs [`iam-policy-autopilot`](https://github.com/awslabs/iam-policy-autopilot)
per changed stack, right after the summarization CLIs (tf-summarize / tfplan2md).
The existing `terragrunt show -json` output (`<stack>.show.json`) is
fed to `iam-policy-autopilot generate-policies`, which maps the plan's resource
changes to IAM actions and emits **advisory least-privilege identity-based IAM
policies**:

- `generate-policies <stack>.show.json --pretty` → printed to the job log
  (stdout is pure JSON; logs go to stderr).
- `generate-policies <stack>.show.json --pretty` → saved as
  `.terragrunt-plans/reports/<stack>.iam-policies.json` (kept only when stdout
  is valid JSON; on failure the diagnostics land in
  `<stack>.iam-policies.stderr.txt`). The pretty artifact is what the MR note
  embeds, so it renders with newlines; a compact copy
  `<stack>.iam-policies.compact.json` (`jq -c`) is kept alongside for
  storage/processing.
- `post_plan_note preview` appends the section
  `## 🔐 IAM policies suggested by iam-policy-autopilot (advisory)` — rendered
  by `render_iam_policies_md` (hidden template `.iac-plan-iam-policies`) — to
  the **same single self-updating MR plan note**: per-stack collapsed
  `<details>` with ` ```json ` fenced (already pretty) policies + a `jq`
  statement count, plus a hint that `Warnings` flag statements that fell back
  to `"Resource": "*"`, followed by a `-- ` signature line after each
  `</details>` so GitLab anchors the closing tag in its own paragraph (and the
  fence cannot swallow it, even without the artifact's trailing newline). No
  extra GitLab API calls.

Safety & scope:

- The binary is expected in the pipeline image at
  `/usr/local/bin/iam-policy-autopilot` (a `PATH` fallback is probed). When
  absent, only a skip NOTE is printed — the plan never fails.
- Every invocation is `|| true`, so a tool failure never fails the plan job.
- `plan-main` / `apply` do not generate or publish policies;
  `post_plan_note main` explicitly does not append them to the deployable-plan
  commit comment.
- The policies are always generated and kept as artifacts; set
  `IAM_POLICY_AUTOPILOT_TO_MR_COMMIT: "false"` to skip appending them to the
  MR note (e.g. when many resources change -> the generated policies would
  make the MR comment very large). A `NOTE:` line in the job log records when
  the note append was skipped.
- The pretty JSON is also echoed to the job log (the job trace); set
  `IAM_POLICY_AUTOPILOT_APPEND_TO_JOB_LOG: "false"` to keep the log small on
  large diffs (a `NOTE:` line records the skip; the artifacts and the
  optional MR comment still exist).
- The per-stack `.show.json` is now deleted at the end of the loop (after
  policy generation), instead of right after tfplan2md.
- Planned follow-up: extract the AWS region/account from the Terragrunt inputs
  and pass `--region` / `--account` to scope the generated ARNs (currently
  wildcard where unknown).
