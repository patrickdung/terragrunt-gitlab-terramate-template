# Terraform, Terragrunt and Terramate

* IaC with Terraform (TF) / OpenTofu (tofu), Terragrunt (TG) and Terramate (tm)
  Give some useful instructions to AI about using IaC like TF/tofu/TG/tm. Prevent hallucinations. Use when generating, reviewing, refactoring, or migrating IaC and when building delivery/testing pipelines.

* Terraform (TF) or OpenTofu (tofu) is the tool or basic element that interact with AWS/on-premise resources or settings.

* Terragrunt (TG) is the orchestration tool for Terraform / OpenTofu. It can break down a large IT resources into separated modules.

* Terramate (tm) is an IAC development/integrated tool that mainly provides detection of change of IaC resources (based on git repository). Where Gitlab CICD and TG are not designed for this (change detection).

* When working with this repository, check the documention in `root-dir-of-repo/SKILL.md`
  Load references from `root-dir-of-repo/iac-references/` if necessary and if the directory exists.

# Instructions

## 1) File Structure

```
root-dir-of-repo/               # This repo
├── AGENTS.md                   # This file, for AI agents like Claude / Codex
├── CHANGELOG.md                # Put major changes into CHANGELOG.md
├── README.md                   # readme
```

## 2) General instructions

- Focus on parts where it is asked to do.
- Do not attempt to delete or fix other codes that is not related and/or not broken.
- If serious problems in other parts were found, prompt or give suggestions
- Try to keep the coding style of current repo.
