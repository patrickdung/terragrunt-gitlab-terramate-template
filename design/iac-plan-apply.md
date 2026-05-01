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
| `TF_STATE_ARTIFACT_ENCRYPTION_KEY` | Passphrase used to encrypt/decrypt binary Terraform plan files. | Undefined |
