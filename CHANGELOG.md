# Changelog

All notable changes to this template repository are documented in this file.

## 2026-10-19

### Added (IaC approval gate — CE-compatible MR approval enforcement)

- **`templates/iac-approval-gate.yml`** (new) — enforces merge-request
  approvals on GitLab CE (no Premium features). Three jobs share one gate
  script:
  - `approval-gate-mr` (own stage `approval-gate`, after `security-check`,
    MR pipelines only) — blocks
    the merge via the project's "Pipelines must succeed" setting. Runs after
    `plan` on purpose: the approver needs to read the plan preview before
    approving. Consumers MUST declare the `approval-gate` stage in their own
    `stages:` list (arrays do not merge across includes; the consumer's list
    wins).
  - `approval-gate-main` (stage `syntax-check`, push-to-`main` pipelines
    only) — fail-fast defense-in-depth; blocks `plan-main` via stage
    ordering, hence `apply`.
  - `approval-gate-plan-review` (stage `approval-gate`, push-to-`main` pipelines
    only, `when: manual`) — the plan-review approval act: the approver
    reads `plan-main`'s saved plan/summaries, then clicks play. For a
    manual job GitLab sets `GITLAB_USER_LOGIN`/`GITLAB_USER_ID` to the
    user who clicked; the gate verifies the clicker is in the effective
    approver pool (plus re-checks the frozen MR approvals). The clicker
    check is **1-of-N** (the clicker must be in the pool — one
    qualifying act, not a count), an additional requirement on top of
    the frozen-approvals re-count, not a replacement for it; the click
    does not add to the count (the MR is locked post-merge). `apply`
    declares a NON-optional need on this job — apply cannot start until a
    pool member clicked, and neutering the job in a consumer MR fails
    pipeline creation loudly (no silent skip).
  - The gate counts approvals from the effective approver pool — cloned
    from a centrally-governed `iac-approvers` repo with the ephemeral
    `CI_JOB_TOKEN` as (global ∪ per-project additions) − per-project
    exclusions — that are not stale (given before the MR's source-branch
    HEAD commit) and not the MR author (author-exclusion mode, default on).
    The threshold comes from the approvers repo (`projects/<id>/required.txt`,
    then root `required.txt`) and wins over the consumer's
    `IAC_APPROVAL_REQUIRED` — central policy cannot be switched off from
    a consumer MR. Everything fails closed (direct pushes to `main`, missing
    or invalid central files, empty pool, unset `IAC_APPROVERS_REPO_URL`,
    rejected API calls). On failure the job log prints a full audit of every
    approval click (`COUNTS` / `author (excluded)` / `stale (before last
    push)` / `not in pool`).
  - The staleness comparison is timezone-safe: the commits API may return
    `created_at` with the server's local UTC offset while `approved_at` is
    UTC Z-format; both are normalized
    to UTC Z-format ISO-8601 by a jq `toz` def (`fromdateiso8601`-based,
    jq-1.7-compatible) before the string comparison.
  - Ships its own inline CA-trust `before_script`
    (`.iac_template_gate_ca_init`, a copy of the apply job's CA block — no
    `apk add`, no network) so the gate works on air-gapped runners against a
    self-signed-CA GitLab by default.
  - The gate jobs download no artifacts (`dependencies: []` — the gate
    reads nothing from the consumer repo). GitLab API debugging: every call
    logs which auth path served it (job-token vs stored token), and when a
    call fails for good the log shows why the job-token attempt was
    rejected (401 vs 404 vs TLS). The auth path is tracked via a temp file
    (a plain `GL_API_AUTH` variable was dead code — `gl_api` always runs
    inside a command substitution/pipeline, so its assignment never
    reached the parent shell).
- **`templates/iac-base.yml`** — new gate variables:
  `IAC_APPROVAL_REQUIRED` (default `"1"`), `IAC_APPROVAL_EXCLUDE_AUTHOR`
  (default `"true"`), `IAC_APPROVERS_REPO_URL` (default `""` — the gate
  fails closed when unset), and `IAC_APPROVERS_REF` (default `"main"`).
  There is deliberately no template-version variable: GitLab exposes no
  variable for the resolved ref/SHA of an `include:project` file, so the
  gate-logic version in force is the template `ref` pinned in the consumer's
  `include` line (see design/iac-approval-gate.md).
- **`templates/iac-plan-apply.yml`** — `apply` now declares
  `needs: [approval-gate-main, optional: true]`. `optional` is
  load-bearing: consumers that do not include the gate file must not get a
  pipeline-creation failure; with the gate included, `apply` cannot start
  unless the main gate passed. `apply` also declares a NON-optional need on
  `approval-gate-plan-review` — apply cannot start until a pool member
  clicked the manual plan-review job; consumers that do not include the gate
  file get a loud pipeline-creation failure (correct: without the gate there
  is no plan-review approval act; they must override `apply`'s needs
  explicitly to run apply ungated).
- **`design/iac-approval-gate.md`** (new) — consumer documentation: wiring,
  variables, tokens (job-token allowlist clone; `read_api` fallback token,
  Reporter role sufficient, masked + unprotected), the project-settings
  checklist (Pipelines must succeed, delete source branch on merge,
  protected `main`), CE retry UX, edge cases, verification checklist, threat
  model and upgrade paths (Premium native rules; external webhook server).
- **`README.md`** — new "IaC Approval Gate (CE)" section, the gate include
  in the consumer example, the `approval-gate` stage in the example stages
  list, and the gate variables in the CI/CD variables list.

### Changed (security scanners are advisory)

- **`templates/upload-reports-to-defectdojo.yml`** — the DefectDojo `upload`
  job is now advisory (`allow_failure: true`): a DefectDojo outage (502)
  must not block the merge — the approval gate is the merge blocker, report
  uploads are telemetry. A failed
  upload shows as a warning (orange) in the pipeline, and the job can be
  retried once DefectDojo is back.
- **`templates/iac-security.yml`** — the security scanners are now
  advisory (`allow_failure: true`): `check-custom-kics`, `check-checkov`,
  `check-terrascan`, `check-custom-gitleaks`, `check-trivy`, and the two
  SAST converters (`check-terrascan-to-sast-gl-by-semgrep`,
  `check-trivy-to-sast-gl-by-semgrep`). Findings are still visible in the
  pipeline (orange warning) and in the SAST reports, but they no longer
  block the merge — the approval gate is the merge blocker. Syntax checks
  (`syntax-tflint`, `terragrunt-hcl-validate-use-prebuilt-container`,
  `check-branch-freshness`) stay blocking.

## 2026-10-14

### Changed (stack dependency ordering — DAG-aware plan/apply)

- **`templates/iac-base.yml`** — new global variable
  `IAC_TERRAMATE_PLAN_EXTRA_FLAGS` (default
  `"--include-all-dependents --run-order"`). Appended to
  `terramate list --changed` in the plan jobs. Set to `""` in a consumer
  repo to restore the old behaviour (changed stacks only, path order).
- **`templates/iac-plan-apply.yml`** — `plan-mr-preview` and `plan-main` now
  run `terramate list --changed ${IAC_TERRAMATE_PLAN_EXTRA_FLAGS}`:
  - `--include-all-dependents` — if stack A changed, stacks that depend on
    A (via Terragrunt `dependency` blocks) are also planned, because their
    inputs may change.
  - `--run-order` — the stack list is sorted in dependency (DAG) execution
    order, so the per-stack plan loop processes dependencies before
    dependents. `plan-main` writes `plan-manifest.txt` in this order.
  - Both plan jobs fail fast on dependency cycles: a `terramate list
    --run-order` sanity check aborts the job with a clear error before any
    planning starts.
- **`templates/iac-plan-apply.yml`** — the `apply` job sanity-checks that
  the manifest order matches `terramate list --run-order` filtered to the
  manifest entries and warns (non-fatal) on mismatch. Apply iterates the
  manifest in the order `plan-main` wrote it (DAG order), so dependencies
  are applied before dependents.
- **`design/iac-plan-apply.md`** — new "Stack dependency ordering (DAG)"
  section documenting the DAG source (Terragrunt `dependency` blocks in each
  stack's root `terragrunt.hcl`), the plan/apply ordering behaviour, the
  toggle variable, and the consumer requirement for `mock_outputs` +
  `mock_outputs_allowed_terraform_commands` (which **must include
  `"show"`** — the plan loop runs `terragrunt show -json` right after
  `terragrunt plan`, and `show` re-resolves dependency outputs too) on
  dependencies that do not exist yet. Also documents that a first-time
  deploy of a dependency chain takes one pipeline run per link (OpenTofu's
  saved-plan variable mismatch check is by design; re-run the pipeline, do
  not retry the apply job).
- **`README.md`** — "Other aspects" now mentions DAG-ordered plan/apply and
  the `mock_outputs` requirement for new dependent stacks.

## 2026-09-07

### Added (iam-policy-autopilot switches + review fixes)

- **`templates/iac-plan-apply.yml`** — new plan-base variable
  **`IAM_POLICY_AUTOPILOT_TO_MR_COMMENT`** (default `"true"`). The
  iam-policy-autopilot policies are **always** generated and kept as
  `plan-mr-preview` artifacts
  (`.terragrunt-plans/reports/<stack>.iam-policies.json` + a compact
  `<stack>.iam-policies.compact.json` copy). Set it to `"false"` in a consumer
  repo to **skip appending the policies to the MR plan note** — useful when
  many resources change and the generated policies would make the MR comment
  very large. A `NOTE:` line in the job log records when the append was
  skipped. `post_plan_note main` and `apply` are unchanged (policies remain
  MR-preview-only).
- **`templates/iac-plan-apply.yml`** — new plan-base variable
  **`IAM_POLICY_AUTOPILOT_APPEND_TO_JOB_LOG`** (default `"true"`). The pretty
  per-stack JSON is also echoed to the `plan-mr-preview` **job log** (the job
  trace, not the MR comment); set it to `"false"` to keep the log small when
  many resources change. The artifacts and the optional MR comment are
  unaffected. A `NOTE:` line records the skip.

### Changed

- **`templates/iac-plan-apply.yml`** — the `.iam-policies.json` artifact is now
  saved from the **`--pretty`** run (previously the compact flag-less run), so
  the JSON embedded in the MR note renders with newlines instead of one long
  line; a compact `<stack>.iam-policies.compact.json` copy (`jq -c`) is kept
  alongside for storage/processing.
- **`templates/iac-plan-apply.yml`** — `render_iam_policies_md` now appends a
  `-- ` signature line after each `</details>` so GitLab anchors the closing
  tag in its own paragraph (the JSON fenced block could otherwise swallow the
  trailing `</details>`, and the artifact's trailing newline is stripped by
  the shell).
- **`README.md` / `design/iac-plan-apply.md`** — documented the
  `IAM_POLICY_AUTOPILOT_TO_MR_COMMENT` and
  `IAM_POLICY_AUTOPILOT_APPEND_TO_JOB_LOG` switches, the pretty-artifact
  change, and the `-- ` note anchor.

## 2026-09-07

### Added (iam-policy-autopilot integration — MR preview only)

- **`templates/iac-plan-apply.yml`** — `plan-mr-preview` now runs
  [`iam-policy-autopilot`](https://github.com/awslabs/iam-policy-autopilot)
  per changed stack, right after the summarization CLIs (tf-summarize /
  tfplan2md). It feeds the existing
  `terragrunt show -json` output (`<stack>.show.json`) to
  `generate-policies` to derive **advisory least-privilege IAM identity
  policies** from the Terraform plan.
  - **Console/note:** `generate-policies <stack>.show.json --pretty` is printed
    to the job log (logs go to stderr, so stdout stays pure JSON).
  - **Artifacts:** a `generate-policies <stack>.show.json --pretty` run is saved
    as `.terragrunt-plans/reports/<stack>.iam-policies.json` — only when stdout
    really is the JSON envelope; a compact `<stack>.iam-policies.compact.json`
    copy is kept alongside; on failure the file is discarded and the
    diagnostics are kept in `<stack>.iam-policies.stderr.txt` (kept only when
    non-empty). `*.iam-policies.json` files never mix with the
    `plan-main-save-plan-summary` long-lived artifact (that job only re-saves
    `reports/`, and the preview reports stay in the preview artifact).
  - **MR note:** a new hidden template `.iac-plan-iam-policies` provides
    `render_iam_policies_md`, which `post_plan_note preview` appends to the
    **same single self-updating advisory MR note** as a
    `## 🔐 IAM policies suggested by iam-policy-autopilot (advisory)` section —
    per-stack collapsed `<details>` blocks with ` ```json ` fenced policies and
    a `jq`-computed statement count, plus a hint that `Warnings` flag
    statements that fell back to `"Resource": "*"`, and a `--` signature
    after each `</details>` (paragraph anchor). The `.iam-policies.json`
    artifact is the `--pretty` output so the note renders with newlines; a
    `<stack>.iam-policies.compact.json` copy is kept alongside. No extra
    GitLab API calls; inherits the note's 900 kB truncation + delete/repost
    idempotency.
  - **Telemetry:** `DISABLE_IAM_POLICY_AUTOPILOT_TELEMETRY: "true"` is exported
    (env var has the highest precedence — beats the persisted
    `~/.iam-policy-autopilot/config.json` choice), plus a best-effort
    `iam-policy-autopilot telemetry --disable` once per job and per stack as a
    persisted fallback. No telemetry is sent.
  - The binary is expected in the pipeline image at
    `/usr/local/bin/iam-policy-autopilot` (`${IAC_PIPELINE_IMAGE}`, see
    `atlantis-custom-image`); a `PATH` fallback is also probed. When absent,
    only a skip NOTE is printed — the plan is never failed. All invocations are
    `|| true` so a tool failure can never fail the plan job.
  - `plan-main` / `apply` are **unchanged**: `post_plan_note main` logs that
    the policies are MR-preview-only and does not append them to the
    deployable-plan commit comment. The per-stack `.show.json` is now removed
    at the end of the loop (after policy generation) instead of right after
    tfplan2md.

### Changed

- **`templates/iac-plan-apply.yml`** — new plan-base variable
  `DISABLE_IAM_POLICY_AUTOPILOT_TELEMETRY: "true"` (see above). Override to
  `"false"` in a consumer repo only if you explicitly want telemetry.
- **`README.md`** / **`design/iac-plan-apply.md`** — documented
  `iam-policy-autopilot` as a required image tool, the MR-preview policy
  generation flow, the advisory/never-fails semantics, the telemetry opt-out
  variable, and the planned `--region`/`--account` follow-up (region/account
  extraction from Terragrunt inputs).

## [2026-09-06]

### Added (IAM Roles Anywhere support)

- **`templates/iac-base.yml`** — new `.iac_template_aws_ra_init` anchor.
  Writes a `[profile ra]` section to `~/.aws/config` with a `credential_process`
  pointing to `aws_signing_helper` (Roles Anywhere credential helper, installed in
  the pipeline image at `/usr/local/bin/aws_signing_helper`). At runtime,
  Terraform/Terragrunt picks it up via `AWS_PROFILE=ra`, obtaining short-lived
  STS credentials without any static AWS access keys.

- **`templates/iac-base.yml`** — new `AWS_RA_ENABLED` variable (default
  `"false"`). The anchor is **a complete no-op** unless the consumer repo sets
  `AWS_RA_ENABLED: "true"` in its own `.gitlab-ci.yml`. Other consumers are
  completely unaffected.

- **`templates/iac-plan-apply.yml`** — added `- !reference
  [.iac_template_aws_ra_init, script]` to `.iac_template_plan_base`
  before_script (covers `plan-main` + `plan-mr-preview`) and to the `apply`
  job's before_script. Both fail fast with a clear `ERROR:` message if any
  `AWS_RA_*` variable is set but incomplete/missing.

- **New optional CI/CD variables** (all prefixed `AWS_RA_*`):

  | Variable | Type | Protected | Masked | Purpose |
  |----------|------|-----------|--------|---------|
  | `AWS_RA_ENABLED` | env var | — | — | Set to `"true"` in consumer `.gitlab-ci.yml` to activate RA |
  | `AWS_RA_TRUST_ANCHOR_ARN` | env var | — | — | Roles Anywhere trust anchor ARN (non-secret, safe in git) |
  | `AWS_RA_PROFILE_ARN` | env var | — | — | Roles Anywhere profile ARN (non-secret, safe in git) |
  | `AWS_RA_ROLE_ARN` | env var | — | — | IAM role ARN to assume (non-secret, safe in git) |
  | `AWS_RA_REGION` | env var | — | — | AWS region (default `us-east-2`) |
  | `AWS_RA_CLIENT_CERT_FILE` | File | ✅ | — | Runner x509 client cert (public material) |
  | `AWS_RA_CLIENT_KEY_BASE64` | Variable | ✅ | ✅ | `base64 -w0` of the private key PEM |

  `AWS_RA_CLIENT_KEY_BASE64` is used instead of a file because a multi-line PEM
  private key **cannot be masked** as a GitLab CI/CD variable. Base64 is a
  single-line string so it both masks correctly and decodes back with `base64 -d`
  at runtime. The decoded key is written to `${CI_PROJECT_DIR}/.aws-ra-client.key`
  (mode 400) and is removed if it fails a PEM sanity check.

### Added

- **Plan notes (`templates/iac-plan-apply.yml`)**: new shared helper
  `.iac-plan-notes` defining `post_plan_note preview|main`.
  - `plan-mr-preview` now posts **one self-updating advisory plan note on the MR**
    via the notes API (tfplan2md markdown only). Re-pushing replaces the previous
    note instead of spamming the MR. Requires `GITLAB_API_TOKEN` (masked, **not**
    protected) — skipped non-fatally when unset.
  - `plan-main` now posts the deployable plan as a **commit comment** on
    `CI_COMMIT_SHA` (renders markdown on the commit page). Pipelines/jobs have
    no notes API and no job-summary surface in GitLab (`CI_JOB_SUMMARY` is
    GitHub Actions only), so the commit comment is the only post-MR notes
    surface. It **never** posts to the MR; idempotent on job retries via
    check-then-post (commit comments have no DELETE API).
- **tf-summarize artifacts**: both plan jobs now save per-stack
  `<stack>.tf-summarize.md` (markdown table) and `<stack>.tf-summarize.html`
  (styled HTML document) under `.terragrunt-plans/reports/`, and print the
  markdown in the job log inside a collapsible ANSI section
  (`section_start`/`section_end`). tf-summarize output is not posted to MR notes.
  - **Flag fix**: `-md`/`-html` cannot be combined with `-tree`/`-draw` —
    `-tree` + `-md` is a hard error, and `-tree` + `-html` is *silently ignored*
    (the writer selection prefers `-tree`), which previously produced an ASCII
    tree in the `.html` artifact. The HTML artifact is now wrapped in a minimal
    styled document so it opens correctly in a browser.
- **`templates/iac-plan-apply.yml` — new `plan-main-save-plan-summary` job** (stage `plan`,
  `needs: [plan-main]` w/ artifacts, main-branch only, `GIT_STRATEGY: none`,
  `cache: []`). It downloads `plan-main`'s artifact, deletes any
  `.terragrunt-plans/*.tfplan${PLAN_ENCRYPTED_SUFFIX}` (defence in depth), then
  re-uploads `.terragrunt-plans/` with **no `expire_in`**. The summaries
  (`reports/*.{plan.md,tf-summarize.md,tf-summarize.html,plan.txt,...}`,
  `plan-manifest.txt`, `plan-notes.md`) therefore stay browsable after
  `plan-main`'s own artifact expires. GitLab expires a whole artifact archive at
  once, so without this follower the reports would disappear together with the
  encrypted plans. `plan-main`'s artifact still carries `expire_in: 3 hours` —
  only the sensitive leftovers (encrypted plans + manifest) vanish at that
  point; the deployable plan must be applied within 3 hours of `plan-main`.
- Saved summaries are reachable at the branch artifact URL
  `${CI_PROJECT_URL}/-/jobs/artifacts/<ref>/browse/.terragrunt-plans/reports?job=plan-main-save-plan-summary`.
  Both the `plan-main` log banner and the main-mode commit comment now link there.

### Changed

- **`templates/iac-plan-apply.yml` — apply job artifact deletion hardened.**
  After the last module is applied, `apply` looks up the successful `plan-main`
  job in the pipeline (status filter + `per_page`) and calls
  `DELETE /projects/:id/jobs/:id/artifacts` (via `GITLAB_API_TOKEN`) so the
  encrypted saved plan cannot be re-applied a second time within the
  `expire_in` window. Reports/summaries are *not* lost:
  `plan-main-save-plan-summary` already saved them (no expiry) before `apply`
  runs. `CI_JOB_TOKEN` cannot delete artifacts (API restriction), so this
  requires `GITLAB_API_TOKEN` (masked, `api` scope). Non-fatal on failure —
  `plan-main`'s `expire_in` is the fallback.
- **Hidden job renames (breaking for consumers overriding them)**:
  `.terramate_template_plan_base` → `.iac_template_plan_base`,
  `.terramate_template_local_ca_init` → `.iac_template_local_ca_init`.
  New shared helper is `.iac-plan-notes`. Repository/project names and
  `terramate` CLI invocations are unchanged.

## [2026-08-29]

### Changed

- **`templates/iac-plan-apply.yml`**: The `apply` job now uses
  `PRIVATE-TOKEN: ${GITLAB_API_TOKEN}` instead of `JOB-TOKEN: ${CI_JOB_TOKEN}`
  for the API calls that delete `plan-main` artifacts after a successful apply.
  - **Reason**: The GitLab CI/CD job token (`CI_JOB_TOKEN`) is restricted to
    download-only access for the Job Artifacts API and can only access `GET /job`
    in the Jobs API. It cannot list pipeline jobs
    (`GET /projects/:id/pipelines/:pipeline_id/jobs`) or delete artifacts
    (`DELETE /projects/:id/jobs/:job_id/artifacts`). The previous code silently
    failed at the first call, so the DELETE was never attempted.
  - **New required variable**: `GITLAB_API_TOKEN` — a project or group access
    token with `api` scope and Maintainer/Owner role. Add it as a masked CI/CD
    variable in the project or group settings.
  - **Non-fatal**: If `GITLAB_API_TOKEN` is unset or the deletion request fails,
    the apply job still succeeds. A `WARNING` message is printed in the job log.

## [2026-08-26]

### Changed

- **`templates/iac-security.yml`**: Added `cache: []` to the iac-security jobs
  (`terragrunt-hcl-validate-use-prebuilt-container`, `check-branch-freshness`,
  `check-checkov`, `check-terrascan`, `check-terrascan-to-sast-gl-by-semgrep`,
  `check-trivy`, `check-trivy-to-sast-gl-by-semgrep`) to avoid inheriting the
  global cache.
- **`templates/iac-security.yml`**: `check-checkov` now uses
  `dependencies: []` so it does not fail when it cannot download artifacts of
  other failed jobs.

## [2026-05-21]

### Changed

- **`.gitlab-ci.yml`**: Updated include names from `terramate-*` to `iac-*`
  to match the renamed template files.

## [2026-05-20]

### Changed

- **`design/iac-plan-apply.md`**: Noted that `TF_STATE_ARTIFACT_ENCRYPTION_KEY`
  should be set as protected and masked in GitLab.

## [2026-05-07]

### Changed

- **`README.md`**: Updated documentation.

## [2026-05-05]

### Changed

- **`README.md`**: Documented one more known issue/behavior.

## [2026-05-02]

### Changed

- **`README.md`**: Updated documentation.

## [2026-05-01]

### Added

- **LICENSE**: Added the repository license file.
- **`AGENTS.md`**, **`README.md`**, **`design/`**: Added the agent
  instructions, readme, and design documentation.
- **Templates**: Added all template files — `iac-base.yml`,
  `iac-plan-apply.yml`, `iac-security.yml`,
  `upload-reports-to-defectdojo.yml`, `custom-homelab-defaults.yml`,
  `debug-vault-helpers.yml` — plus `.gitlab-ci.yml` and `.tflint.hcl`.
