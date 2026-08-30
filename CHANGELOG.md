# Changelog

All notable changes to this template repository are documented in this file.

## [2026-08-30]

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
