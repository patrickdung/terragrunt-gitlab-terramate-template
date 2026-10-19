# IaC Approval Gate

`templates/iac-approval-gate.yml` enforces merge-request approvals on GitLab
**CE** (no Premium features): it fails the pipeline when an MR does not have
the required approvals from a centrally-governed approver pool, and — combined
with the project's **"Pipelines must succeed"** setting — actually blocks the
merge button.

GitLab CE lets you configure approval rules in the UI, but they are **not
enforced** without a license: anyone with merge permission can merge
regardless of approval state. The CE `/merge_requests/:iid/approvals` API
endpoint *does* report who clicked Approve, so the gate reads it and enforces
the policy in CI.

The approver pool and thresholds live in a separate, centrally-governed repo
(`iac-approvers`); the full design, governance model and maintenance
procedures are documented in that repo's `design.md`. This page covers
consumer-side wiring only.

## How it works

The gate counts an MR's approvals that:

1. come from the **effective approver pool** — cloned from the iac-approvers
   repo as (global `approvers.txt` ∪ `projects/<id>/approvers.txt`) −
   `projects/<id>/exclusions.txt`;
2. are **not stale** — given before the MR's source-branch HEAD commit do not
   count (CE may keep approvals across pushes);
3. are **not the MR author** — unless `IAC_APPROVAL_EXCLUDE_AUTHOR=false`
   (solo-maintainer mode; the audit output labels it explicitly).

The threshold comes from the iac-approvers repo
(`projects/<id>/required.txt`, then root `required.txt`) and **wins over the
consumer's `IAC_APPROVAL_REQUIRED`** — central policy cannot be switched off
from a consumer MR. Everything fails closed: direct pushes to `main`, missing
or invalid central files, an empty pool, an unset `IAC_APPROVERS_REPO_URL`,
rejected API calls.

On failure the job log prints a full audit: every approval click classified
as `COUNTS` / `author (excluded)` / `stale (before last push)` /
`not in pool` — the "why is the gate red when Alice approved" answer is
always in the log.

## Enforcement points

| Point | Job | Stage | Blocks |
|---|---|---|---|
| Pre-merge (MR pipeline) | `approval-gate-mr` | `approval-gate` (own stage, after `security-check`) | the merge, via "Pipelines must succeed" |
| Post-merge (push to `main`) | `approval-gate-main` | `syntax-check` (first stage) | `plan-main` via stage ordering, hence `apply` |
| Apply backstop | `apply` declares `needs: [approval-gate-main, optional: true]` | — | `apply` cannot start unless the main gate passed |
| Plan-review approval | `approval-gate-plan-review` (manual) | `approval-gate` (after `plan-main`) | `apply` via a NON-optional need — the play-click is the approval act |

Notes:

- **`approval-gate-plan-review` is the "act on the reviewed plan" step.** It is
  `when: manual` in the `approval-gate` stage, so its play button appears
  once `plan-main` finishes. The approver reads the saved plan/summaries,
  then clicks play — for a manual job GitLab sets
  `GITLAB_USER_LOGIN`/`GITLAB_USER_ID` to the user who clicked, and the
  gate verifies that user is in the effective approver pool (plus
  re-checks the frozen MR approvals). `apply` declares a **non-optional**
  need on it: apply cannot start until a pool member clicked, and a
  consumer MR that neuters the job fails pipeline creation loudly
  ("apply job needs approval-gate-plan-review, but it was not added to the
  pipeline") — no silent skip. Consumers that do not include the gate
  file get the same loud failure — correct, since without the gate there
  is no plan-review approval act; they must override `apply`'s needs
  explicitly (a visible change) to run apply ungated.
- **The clicker check is 1-of-N, not M-of-N.** The Step 4 membership
  check requires the play-clicker to **be in the pool** — one
  qualifying human act, not a count. It is an *additional* requirement
  on top of the frozen-approvals re-count, not a replacement for it:
  the count (M-of-N) proves the MR was approved pre-merge; the
  clicker check (1-of-N) attributes the plan-review act to a pool
  member at apply time. The click does **not** add to the count — the
  MR is locked post-merge, so it cannot be recorded as a GitLab
  approval; it is a separate, attributable act recorded in the job
  log. If a future policy needs M-of-N at apply time (e.g. two
  operators must click), the natural extension is M sequential manual
  jobs each verifying a *different* clicker — deferred until a real
  need exists.

- The MR gate runs in its **own `approval-gate` stage, after `security-check`**
  on purpose: the approver needs to read the plan (and see the advisory
  scanner results) before approving, and in GitLab a failed job in an earlier
  stage prevents all later stages from running. A gate in an earlier stage
  would block the plan preview exactly when the approver needs it most.
- **Only the gate blocks the merge.** Every other job is advisory
  (`allow_failure: true`): the security scanners and the DefectDojo
  `upload` job. A DefectDojo outage (502) or a scanner crash shows as a
  warning (orange) in the pipeline but never blocks the merge — found in
  production: pipeline 856's `upload` failed with 502 (djnginx stuck in
  `Created`) and, with "Pipelines must succeed" enforced, blocked a
  fully-approved MR from merging.
- **The consumer MUST declare `approval-gate` in its own `stages:` list**
  (after `security-check`). `stages` is an array and arrays do **not** merge
  across includes — when the consumer declares `stages:`, its list wins
  entirely and the template's stage declarations are ignored (verified on the
  instance: a job referencing an undeclared stage fails pipeline creation
  with "chosen stage approval-gate does not exist"). The template's own
  `stages:` block only takes effect for consumers that declare no `stages:`
  at all.
- The main gate fails **fast** in the first stage (approvals are frozen
  post-merge; no plan-preview concern) and saves the plan compute when it
  catches a merge that slipped past the MR gate.
- `optional: true` on apply's need is load-bearing: consumers that do **not**
  include the gate file must not get a pipeline-creation failure.
- The main gate only runs for `$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == "main"`.
  Scheduled/webhook/manual pipelines have no merge-commit MR to resolve and
  would fail closed forever; if a manual `main` pipeline should be gated too,
  add `|| $CI_PIPELINE_SOURCE == "web"` consciously.

## Wiring

Add the include to the consumer's `.gitlab-ci.yml` (pinned to a tag or SHA,
like the other template files):

```yaml
include:
  - project: 'homelab/tg-s3-gl-terramate-template'
    ref: 'v0.12'          # pin to a tag or commit SHA
    file:
      - 'templates/iac-security.yml'
      - 'templates/iac-plan-apply.yml'
      - 'templates/iac-approval-gate.yml'   # <-- the gate
```

The gate file declares `syntax-check`, `security-check` and `approval-gate`
in its own `stages:` block, but that block only takes effect when the consumer
declares **no** `stages:` of its own — `stages` is an array and arrays do not
merge across includes; the consumer's list wins entirely. Consumers with
their own stage list (like this repo) must add `approval-gate` themselves,
between `security-check` and `upload-reports-to-defect-dojo`.

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `IAC_APPROVERS_REPO_URL` | `""` | Full https clone URL of the iac-approvers repo. **Required** — when empty the gate jobs fail closed (misconfiguration, not "off"). |
| `IAC_APPROVERS_REF` | `"main"` | Branch or tag of the iac-approvers repo to clone. Recommend a pinned tag (`approvers-v1`) in real use; must be a branch/tag name, not a SHA. |
| `IAC_APPROVAL_REQUIRED` | `"1"` | Consumer default threshold. Ignored when a central `required.txt` exists (root or `projects/<id>/`) — central policy wins. `"0"` disables the gate **only** when no central policy exists. |
| `IAC_APPROVAL_EXCLUDE_AUTHOR` | `"true"` | `"true"` — the MR author's own approval never counts (two-eyes rule). `"false"` — it counts (solo-maintainer case). Invalid values fall back to `"true"` with a warning. |
| `IAC_APPROVAL_GITLAB_TOKEN` | unset | Approvals-API fallback token (see Tokens). Only needed if the API rejects the job token. |

**Set these as project-level CI/CD variables in the UI, not YAML** — UI
variables beat YAML variables in precedence, so a developer's MR cannot
override them.

**Gate-logic versioning.** There is deliberately no template-version
variable. GitLab exposes no predefined variable for the resolved ref/SHA of
an `include:project` file, and the gate job cannot know which template ref
the consumer pinned — re-resolving a moving branch at gate-run time would
race template changes and log the wrong version. The authoritative version
record is the template `ref` in the consumer's `include` line (visible in
their `.gitlab-ci.yml`, and changing it is itself an MR the gate reviews).
The approvers-policy version — which governs who may approve — IS logged by
the gate on every run (`iac-approvers: ref=... commit=...`).

## Tokens

- **Allowlist fetch** — none. The gate clones the iac-approvers repo with the
  ephemeral `CI_JOB_TOKEN` (the iac-approvers repo must allowlist the consumer
  project under Settings → CI/CD → Token Access).
- **Approvals API** — the gate tries the job token first; the approvals
  endpoint is not job-token-accessible on CE, so expect the fallback:
  `IAC_APPROVAL_GITLAB_TOKEN` — a project access token with `read_api` scope,
  **Reporter role is sufficient** (the minimum role that can read MR
  approvals; the token user never approves anything, it only reads the
  approvals list). Add it as a **masked**, **unprotected** CI/CD variable —
  MR pipelines run on unprotected source branches and cannot see protected
  variables. Prefer project-level over group-level: an unprotected group
  variable is handed to every pipeline of every project in the group,
  including fork MR pipelines.
- **Main pipelines** — the fallback there is `GITLAB_API_TOKEN` (already
  required by `apply`); no extra variable.

The gate logs which auth path served each call (`GL_API_AUTH`), and when a
call fails for good it also prints why the job-token attempt was rejected
(401 vs 404 vs TLS), so first-time wiring and token-rotation debugging are
not guesswork.

## Project settings checklist (per consumer repo)

- ☑ **Pipelines must succeed** (Settings → Merge requests) — this is the
  setting that links the gate job's exit code to the Merge button.
- ☑ All discussions must be resolved before merge.
- ☑ **Delete source branch when merge request is accepted** — freezes the
  MR's `.sha` at the merged commit; without it, a post-merge push to the
  surviving source branch drifts the staleness cutoff and blocks `apply` for
  a properly-approved merge.
- ☑ Protected branch `main`: Allowed to push **No one**; Allowed to merge =
  specific users (this also restricts who can run manual jobs such as
  `apply` on `main`).

## CE retry UX

On CE, clicking **Approve does not re-run the pipeline**. After the last
required approval, retry the failed gate job (or push a new commit) for the
pipeline to turn green. Real-time re-evaluation on every approval click is
what an external webhook server adds (see Upgrade paths).

## Edge cases

- **Direct push to `main`** → no MR → the main gate fails closed. Correct
  behavior; direct pushes should be impossible anyway (protected branch).
- **Squash merges** → the commit→MR lookup generally associates the squashed
  commit; verify once on the instance with a real squash merge.
- **Fork MRs** → the job token may not be permitted to read the iac-approvers
  repo, so the gate fails closed with a clone error. Recommended policy for
  IaC repos: fork contributions are out of scope — require direct project
  membership.
- **Merged without sufficient approvals** (e.g. forced merge) →
  `approval-gate-main` fails on `main`, and approvals are frozen post-merge.
  Remediation: a properly-approved **revert MR** (approve after its last push,
  then retry the gate job).
- **Leavers / renamed users** → a deactivated or renamed user silently stops
  matching the pool (fail closed). The iac-approvers repo's lint job warns
  on inactive/unresolvable usernames; remove leavers there.

## Verification checklist

Test once per consumer repo (and after any template change):

1. A non-list user approves → gate fails; audit lists the user as
   `not in pool`.
2. An allowlisted (non-author) user approves → retry the gate job → passes
   with `1/1 qualifying`.
3. The MR author (even if in the pool) approves → gate still fails
   (exclusion ON).
4. With `IAC_APPROVAL_EXCLUDE_AUTHOR=false`, the author's approval counts;
   the audit labels it `COUNTS (author — exclusion off)`.
5. With threshold 2: one qualifying approval fails, two pass.
6. Direct push to `main` (scratch repo) → main gate fails closed with the
   "no merged MR" error.
7. Pinned `IAC_APPROVERS_REF` tag: changing the list on the approver repo's
   `main` does not affect the consumer until the ref is bumped.
8. Merge a properly approved MR, run `apply` → the main gate passed and
   apply started (needs satisfied).

## Threat model

The CI gate is a **guardrail, not a lock**. A developer on a consumer repo
can, in their MR:

- delete or neuter the gate jobs (include-merge semantics let the consumer
  override template jobs) — the residual hole; the main gate and the apply
  `needs` backstop live in the template's `main` CI config, so removing them
  requires merging, and merging requires passing the MR gate,
- override YAML-defined gate variables — mitigated by setting them as UI
  variables (UI beats YAML),
- skip the MR pipeline via `workflow:rules`,
- set `IAC_APPROVAL_EXCLUDE_AUTHOR=false` — a deliberate, documented mode,
  but it weakens the gate to self-approval.

Additional hardening notes (from surveying similar open-source gates):

- **`CI_API_V4_URL` is overridable from consumer YAML.** A malicious MR can
  redefine it and the gate would send its fallback token to an attacker's
  host. Mitigation today: the fallback token is `read_api`-scoped (the blast
  radius is one read-only token) and the gate fails closed on any API error.
  A future hardening may derive the API root from `CI_SERVER_HOST` /
  `CI_SERVER_FQDN` and ignore the override, the way
  `KRNichols/gitlab-mr-reviewer` does.
- **The fallback token is passed on curl's argv** (visible in the runner's
  process list while curl runs). GitLab masks it in job logs and it is
  read-only; a future hardening may move it to a `0600` header file
  (`curl -H @file`).
- **`CI_DEBUG_TRACE`** in a consumer MR would echo all variables to the job
  log — do not enable it on repos that carry the fallback token.

For a homelab with a small trusted set, the CI gate + UI variables + pinned
ref + protected merge list is the recommended baseline.

## Upgrade paths

- **Premium/EE license** → native approval rules with named eligible
  approvers replace the pool-intersection logic; the gate switches to
  asserting `GET .../approval_state` → all `rules[].approved == true`.
- **Protected Environments + Deployment Approvals** (Premium) → the
  simplest and most robust replacement for `approval-gate-plan-review`'s
  manual-click pattern: give `apply` an `environment:` (e.g.
  `production`), protect it, and set required deployment approvals with
  the approver pool as allowed approvers. The job stays blocked until
  the right people approve the deployment in the UI — GitLab-native,
  settings-layer enforcement a consumer MR cannot neuter. On CE this is
  unavailable; the manual `approval-gate-plan-review` job is the CE
  equivalent.
- **External webhook server** → closes the CE gaps (real-time re-evaluation
  on every approval click; enforcement outside the repo's control). Prior
  art: `null-ptr-exception/glee` (config-repo rules, author/committer
  exclusion, per-MR overrides), `chrxmvtik/gitlab-mr-conform` (MR conformity
  rules), `cropalato/MergeSentinel` (writes merge status directly to
  GitLab's PostgreSQL — API-only approaches like ours avoid the DB-schema
  coupling).
- **Committer exclusion** (exclude everyone who pushed to the MR, not just
  the author — glee's `prevent_committer_approval`) is a possible future
  extension of the gate script.
