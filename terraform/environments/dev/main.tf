# =============================================================================
# terraform/environments/dev/main.tf
#
# Entry point for the dev environment.
# Calls the gitlab-oidc module to provision an AWS OIDC Provider and IAM Role
# that allows GitLab CI to authenticate to AWS without static credentials.
#
# Before the first apply:
#   1. cp terraform.tfvars.example terraform.tfvars
#   2. Fill in your real values (region, account, etc.)
#   3. Configure a remote backend (S3 + DynamoDB) for production use,
#      or leave the default local backend for demo purposes.
#   4. Run: terraform init && terraform plan && terraform apply
# =============================================================================

# ---------------------------------------------------------------------------
# Remote backend (recommended for production).
# Uncomment and fill in your S3 bucket details before using in a team.
# ---------------------------------------------------------------------------
# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "zero-trust-cicd/dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-state-lock"
#     encrypt        = true
#   }
# }

# ---------------------------------------------------------------------------
# AWS Provider
# ---------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # Uncomment to prevent accidental apply against the wrong AWS account.
  # allowed_account_ids = ["123456789012"]

  default_tags {
    tags = {
      Project     = "zero-trust-cicd-pipeline"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# ---------------------------------------------------------------------------
# GitLab OIDC module
# Provisions the OIDC Provider and the scoped IAM Role for GitLab CI.
# ---------------------------------------------------------------------------
module "gitlab_oidc" {
  source = "../../modules/gitlab-oidc"

  gitlab_project_path  = var.gitlab_project_path
  allowed_refs         = var.allowed_refs
  name_prefix          = var.name_prefix
  iam_policy_arns      = var.iam_policy_arns
  max_session_duration = var.max_session_duration
  tags                 = var.extra_tags
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "gitlab_ci_role_arn" {
  description = "IAM Role ARN for GitLab CI. Set this as the AWS_ROLE_ARN CI/CD variable in GitLab."
  value       = module.gitlab_oidc.gitlab_ci_role_arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider registered in AWS IAM."
  value       = module.gitlab_oidc.oidc_provider_arn
}

output "allowed_sub_claims" {
  description = "Sub claim values embedded in the Trust Policy (for verification)."
  value       = module.gitlab_oidc.allowed_sub_claims
}

output "setup_instructions" {
  description = "Next steps after apply."
  value       = module.gitlab_oidc.setup_instructions
}
