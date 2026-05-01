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

### `.terramate_template_local_ca_init` (Hidden Job/Anchor)
A `before_script` helper that:
1. Detects `ROOT_CA_PATH`.
2. Normalizes line endings (dos2unix).
3. Updates the system trust store (`update-ca-certificates`).
4. Configures `AWS_CA_BUNDLE` and `VAULT_CAPATH` to ensure all tools trust the local CA.

### Shared Job Configuration (`.terramate_template_base`)
All IaC jobs should extend this to inherit:
- The custom `IAC_PIPELINE_IMAGE`.
- Environment variable defaults.

## Workflow Impact

This template must be included first in any pipeline to ensure the environment is correctly primed for security linting and deployment operations. Without the CA initialization, jobs interacting with Vault or Local S3 will fail TLS verification.
