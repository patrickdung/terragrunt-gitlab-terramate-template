# Vault debug helpers Template

The `debug-vault-helpers.yml` template provides utility scripts and jobs for diagnosing authentication and secret retrieval issues between GitLab CI and HashiCorp Vault.

This template is meant for authentication and secret retrieval debugging with Hashicorp Vault .

## Security Warning

These helpers are designed for **development** use. It will display private token for debugging purpuse. You need to create your own cicd config file for production use.
