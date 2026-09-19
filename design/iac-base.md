# Infrastructure as Code (IaC) Base Template

The `iac-base.yml` template serves as the foundation for the Terramate and Terragrunt pipeline. It defines global variables, shared job configurations, and critical initialization logic for local homelab environments (where the self managed GitLab instance is using self-signed SSL certificates).

## Purpose

- **Global Standardization**: Sets default versions for Terraform, Terragrunt, and Terramate.
- **Environment Normalization**: Handles custom Root CA certificate injection for local `.local.nonet` services (like Vault and S3).
- **Resource Management**: Defines the default `IAC_RESOURCE_GROUP` for consistent job organization.
- **Cache Management**: Configures a global GitLab CI cache for Terramate metadata.

## Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `IAC_RESOURCE_GROUP` | GitLab's resource group to prevent two CICD (iac) pipeline to run at the same time. | `terraform-state` |
| `VAULT_ADDR` | Address of the HashiCorp Vault server. | null / undefined |
| `AWS_EC2_METADATA_DISABLED` | Disables EC2 metadata calls (required if your S3 application not supporting it). | `false` (tunable) |

## Core Components

### `.iac_template_local_ca_init` (Hidden Job/Anchor)
A `before_script` helper that:
1. Detects `ROOT_CA_PATH`.
2. Normalizes line endings (dos2unix).
3. Updates the system trust store (`update-ca-certificates`).
4. Configures `AWS_CA_BUNDLE` and `VAULT_CAPATH` to ensure all tools trust the local CA.

### Shared Job Configuration (`.iac_template_base`)
All IaC jobs should extend this to inherit:
- The custom `IAC_PIPELINE_IMAGE`.
- Environment variable defaults.

### `.iac_template_aws_ra_init` (Hidden Job/Anchor)

An opt-in `before_script` helper for consumers that authenticate to AWS via
**IAM Roles Anywhere** (`aws_signing_helper`). It is **disabled by default**
(`AWS_RA_ENABLED: "false"`) and is a no-op unless the consumer explicitly
enables it in its own `.gitlab-ci.yml`.

When enabled, it:

1. Validates all required `AWS_RA_*` variables are present (fail-fast with a
   clear `ERROR:` message if not).
2. Decodes the private key from `AWS_RA_CLIENT_KEY_BASE64` to
   `${CI_PROJECT_DIR}/.aws-ra-client.key` (mode 400).
3. Writes a `[profile ra]` section to `~/.aws/config` with a `credential_process`
   pointing to `/usr/local/bin/aws_signing_helper`.
4. Exports `AWS_PROFILE=ra` and `AWS_REGION` so Terraform/Terragrunt pick up the
   Roles Anywhere credentials automatically.

Required variables (set in consumer `.gitlab-ci.yml`):

| Variable | Purpose |
|----------|---------|
| `AWS_RA_ENABLED` | Set to `"true"` to activate |
| `AWS_RA_TRUST_ANCHOR_ARN` | Roles Anywhere trust anchor ARN |
| `AWS_RA_PROFILE_ARN` | Roles Anywhere profile ARN |
| `AWS_RA_ROLE_ARN` | IAM role ARN to assume |
| `AWS_RA_REGION` | AWS region (optional, default `us-east-2`) |

Required GitLab CI/CD variables (Settings → CI/CD → Variables):

| Variable | Type | Protected | Masked | Purpose |
|----------|------|-----------|--------|---------|
| `AWS_RA_CLIENT_CERT_FILE` | File | ✅ | — | Runner x509 client cert (PEM) |
| `AWS_RA_CLIENT_KEY_BASE64` | Variable | ✅ | ✅ | `base64 -w0` of the private key |

The key is provided as base64 because a multi-line PEM private key **cannot be
masked** as a GitLab CI/CD variable. Base64 is single-line and decodes cleanly.

## Workflow Impact

This template must be included first in any pipeline to ensure the environment is correctly primed for security linting and deployment operations. Without the CA initialization, jobs interacting with Vault or Local S3 will fail TLS verification.
