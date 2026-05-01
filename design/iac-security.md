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
