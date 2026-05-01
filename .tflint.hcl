config {
  force               = false
  call_module_type    = "local"
  disabled_by_default = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
  version = "0.14.1"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "aws" {
  enabled = true
  version = "0.47.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  # region = "eu-north-1"
}

rule "terraform_unused_declarations" {
  enabled = false
}

# General Terraform rules
rule "terraform_deprecated_interpolation" {
  enabled = true
}
 
# Disallow variables, data sources, and locals that are declared but never used.
rule "terraform_unused_declarations" {
  enabled = true
}
 
# Disallow // comments in favor of #.
rule "terraform_comment_syntax" {
  enabled = false
}
 
# Disallow output declarations without description.
rule "terraform_documented_outputs" {
  enabled = true
}
 
# Disallow variable declarations without description.
rule "terraform_documented_variables" {
  enabled = false
}
 
# Disallow variable declarations without type.
rule "terraform_typed_variables" {
  enabled = true
}
