# Infrastructure as Code (IaC) Plan & Apply Template

The `iac-plan-apply.md` template implements the core deployment workflow for multi-stack environments orchestrated by Terramate.

## Purpose

- **Change Detection**: Uses `terramate list --changed` to find modified stacks.
- **Speculative Previews**: Generates "Advisory" plans for Merge Requests. The plan is for viewing only. Another plan for planning will be created after MR is merged.
- **Secure Plan Storage**: Utilize openssl to encrypt binary Terraform plans.
- **Manual Promotion**: Ensures `apply` operations are gated by manual triggers.
- **Reporting**: Generates human-readable summaries of infrastructure changes.

## Key Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TF_STATE_ARTIFACT_ENCRYPTION_KEY` | Passphrase used to encrypt/decrypt binary Terraform plan files. For this variable in GitLab, please remember to set protected and masked | Undefined |
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
