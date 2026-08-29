# Terramate GitLab CI Template

This repository is the source of reusable GitLab CI templates for Terramate and Terragrunt.

The root pipeline in [./.gitlab-ci.yml](./.gitlab-ci.yml) is the template repository's own integration pipeline. It consumes the exported files locally so changes to the shared YAML are exercised in this repository before other repositories adopt them.

## How this template is designed

This template is inspired by [TACOS](https://opentofu.org/docs/intro/tacos/) like Atlantis.
In an ideal situation, use of TACOS like Atlantis, Digger is desirable.
There are some use cases where the users want a pure GitLab CI solution for use with Terragrunt.

So, in this template, it would:

- Try to block users to run two Terragrunt with GitLab pipeline simultaneously (controlled by GitLab resource group)
- Two different users or Git branches dis-regard / overwrite existing changes that is already commited in main branch (controled/checked by check-branch-freshness)
- Applying Terragrunt should only apply a pre-defined Terraform plans. Instead of plan again right before applying.
- Users will be able to preview what would be changed (task 'plan-mr-preview') at merge request (MR).
  - Plain Terraform output is hard to read. Use of tf-summarize and tfplan2md to help users to identify
what would be changed
- If a MR looks good, users can merge the code to the main branch
  - A new pipeline will be created
    - Syntax checking will be run again
    - Terragrunt/Terraform planning (at task 'plan-main'), the Terraform plan will be encrypted and saved as GitLab artifacts
    - If the user wants to apply the Terragrunt code, he/she needs to run the apply task manually in GitLab
    - After the apply task has run successfully, the Terraform plans (artifacts) would be deleted to prevent them to be re-run (accidentially)
- Other aspects
  - Use of Terramate to detect what resources is being changed
  - Security checking
  - I am using a self signed CA certificate for my homelabe environment. So, there would be settings for trusting the self signed CA certificate.

## What configuration is required

- Users need to onboard Terramate with their Terragrunt setting for each Terragrunt directory (needed for existing and new resources in the future)
- GitLab pipeline
  - Refer below for the variables needed

## Known behaviour or known problems

- After the user merges new MR to main, a new pipeline would start.
In that new pipeline:
  - The user needs to review the plan in the plan-main task
  - The user needs to run the apply task manually
  - There is a chance that the user forgets to run the apply task 
  - If another user (or the same user) check out the most update code from the main branch
    - It is allowed for the new code in the new branch / new code to merge to main branch again using a new MR
    - Also, it is allowed for the user to run the apply task after the latest MR is merged to main branch
      - In this case, the latest pipeline should include the changes of resources that have not been applied in the last pipeline
    - If the user goes back to the previous pipeline to run the apply task, it should block
     - It would block because the previous task's git commit id/tip is not pointing to the latest one

- Suppose the plan passed the plan stage. MR is merged.
  A new task is spawn to work on the main branch.
  But the pipeline failed in the middle before it can be applied.
  i.e. the change in the IaC code is not applied to the related resources.
  Another MR is created to fix the problem, but this template/design may not be able to
  detect/aware that there are resource changes that had not been applied.
  This will cause drifting.
  - Users need to cater for these exception
     - e.g. Force the changed code to go thorugh the pipeine again or
     - Revert the changed code

## Exported Include Files

* The templates are located in the `templates/` directory and are designed to be included in other GitLab projects. Detailed documentation for each template can be found in the [design/](design/) folder:

- [Base Configurations & CA Init](design/iac-base.md) - Global variables and TLS normalization.
- [Security Scanning](design/iac-security.md) - Linting (TFLint, KICS and so on.) and reporting.
- [Deployment Workflow](design/iac-plan-apply.md) - Encryption of plan files, MR reporting, and manual applies.
- [Debug Vault Helpers](design/debug-vault-helpers.md) - Authentication and secret retrieval with Hashicorp Vault, **for debugging only**.
- [DefectDojo Integration](design/upload-reports-to-defectdojo.md) - Upload reports to Defectdojo for centralized vulnerability management.
- [Homelab Defaults](design/custom-homelab-defaults.md) - Specifically designed for **a homelab setting. Do not include this in other environments.** Set your own values via CI/CD variables instead.

## Future Consumer Pattern

Future caller repositories should consume these files with `include:project`, pinned to a tag or commit SHA.

Example:

```yaml
workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never

stages:
  - syntax-check
  - plan
  - security-check
  - security-check-to-sast
  - upload-reports-to-defect-dojo
  - apply

include:
  - project: 'homelab/tg-s3-gl-terramate-template'
    # Update the branch/tag in next line
    ref: 'v1.0.0'
    file:
      - 'templates/iac-security.yml'
      - 'templates/iac-plan-apply.yml'
      - 'templates/upload-reports-to-defectdojo.yml'
      # Optional: include only if you use SOPS AGE / Hashicorp Vault for secret retrieval
      # - 'templates/debug-vault-helpers.yml'
```

The caller repository keeps ownership of its Terramate stack definitions, Terragrunt backend configuration, Terraform/OpenTofu code, and project-level CI/CD variables.

## Required CI/CD Variables

- `IAC_PIPELINE_IMAGE` — container image to use for plan/apply jobs
  - You need to have these tools installaed in the IaC pipeline container
    - [Terragrunt](https://github.com/gruntwork-io/terragrunt/)
    - Terraform/OpenTofu - I tested with OpenTofu
    - [Terramate](https://github.com/terramate-io)
    - openssl - For encrypting Terraform state as GitLab artifact
    - [tfsummarize](https://github.com/dineshba/tf-summarize)
    - [tfplan2md](https://github.com/oocx/tfplan2md)
    - [glow](https://github.com/charmbracelet/glow)
- `LOCAL_INTERMEDIATE_CA_CERT_FILE`
- `LOCAL_ROOT_CA_CERT_FILE`
- `TF_STATE_ARTIFACT_ENCRYPTION_KEY`
- `GITLAB_API_TOKEN` — Project or group access token with `api` scope and Maintainer/Owner role. Used by the apply job
 to delete `plan-main` artifacts after a successful apply to prevent replay. If unset, artifact deletion is skipped (n
on-fatal).

## Optional CI/CD Variables

- `SOPS_AGE_KEY` or `SOPS_AGE_KEY_FILE`
- `TFLINT_PLUGIN_GITHUB_TOKEN`
- `DEFECTDOJO_URL`
- `DEFECTDOJO_API_KEY`
- `DEFECTDOJO_ENGAGEMENT_ID`
- `VAULT_ADDR` — required when using Vault helper jobs
- `VAULT_ID_TOKEN_AUDIENCE` — required when using Vault helper jobs
- `VAULT_AUTH_ROLE` — required when using Vault helper jobs

## Common Overrides

These shared defaults can be overridden by caller repositories without editing the template:

- `IAC_PIPELINE_IMAGE` — no default; must be set by the caller
- `IAC_RESOURCE_GROUP`
- `AWS_EC2_METADATA_DISABLED` — defaults to `false`
- `VAULT_AUTH_PATH` — defaults to `jwt`

## Notes

- The shared plan/apply logic preserves the current encrypted saved-plan workflow.
- The optional upload include expects DefectDojo integration variables and should only be included by repositories that use DefectDojo.
- Future caller repositories should pin template consumption to a release tag or commit SHA rather than a moving branch.
