# Infrastructure as Code (IaC) Security Template

The `iac-security.yml` template provides a comprehensive suite of static analysis and security scanning tools to ensure compliance and prevent misconfigurations.

## Purpose

- **Syntax Validation**: Ensures Terraform code is syntactically correct and formatted.
- **Security Linting**: Runs multiple industry-standard engines (TFLint, KICS, Terrascan, Checkov).
- **Standardized Reporting**: Converts disparate scanner outputs into GitLab-compatible SAST and Code Quality reports.
- **Policy Enforcement**: Prevents the introduction of insecure patterns (e.g., public S3 buckets, wide-open security groups).

## Scanning Engines

### 1. TFLint (`syntax-tflint`)
- **Focus**: Cloud-specific best practices and provider-specific errors.
- **Output**: JSON converted to GitLab Code Quality format.

### 2. KICS (`check-custom-kics`)
- **Focus**: Infrastructure-as-code security vulnerabilities and compliance.
- **Configuration**: Uses a custom `kics.config` if present.
- **Note**: Has a 15-minute timeout to prevent hanging on complex stack trees.

### 3. Terrascan (`check-terrascan`)
- **Focus**: Policy-as-code enforcement and auditing for cloud-native infrastructure.

### 4. Checkov (`check-checkov`)
- **Focus**: Scans for security and compliance misconfigurations across cloud providers.

## Report Conversion

In generate reports are created as SARIF generic format.
Some reports are created / converted as:
- GitLab SAST format
- GitLab Junit format
- GitLab Code Quality format

## Workflow Impact

These jobs run in the `security` stage. By default, they are allowed to fail (`allow_failure: true`) to avoid blocking pipelines on non-critical warnings, but they provide essential visibility during the Merge Request review process.

## Known limitation: the security stage scans almost nothing in a Terragrunt repo

Every scanner above (`tflint`, KICS, Terrascan, Checkov, Trivy) inspects
**`.tf` files present in the checked-out repository**. A Terragrunt consumer
repo typically contains **no `.tf` files at all** — modules are pulled at
`terragrunt init` time via `terraform { source = "git::..." }` into
`.terragrunt-cache/`, which the scanners skip (`.terraform`, `.terragrunt-cache`).
The result is a stage that passes green while scanning nothing.

Two mitigations are in place / recommended:

1. **Plan-JSON scan (implemented, `IAC_PLAN_JSON_SCAN_ENABLED`, default
   `"true"`).** Both plan jobs run
   `checkov -f <stack>.show.json --framework terraform_plan` against the
   resolved `terragrunt show -json` output — the only artifact that describes
   the resources that would actually be created, including everything pulled
   from remote modules. Reports land in
   `.terragrunt-plans/reports/plan-scan/<stack>.checkov.json`. Advisory only:
   findings never fail the plan. Requires the `checkov` binary in
   `IAC_PIPELINE_IMAGE`; when absent the scan is skipped with a `NOTE`.
   The raw `.show.json` is deleted right after the scan and is never uploaded
   as an artifact.
2. **Scan the module source repos separately.** The modules themselves are
   plain Terraform and are best scanned where they live (their own pipelines),
   not through the consumer's checkout.

`terragrunt-hcl-validate-use-prebuilt-container` deliberately does **not** run
`terragrunt info print`: it dumps the fully resolved Terragrunt config
(including every local) into the job log, which would expose any SOPS-decoded
value to anyone who can read the job trace.
