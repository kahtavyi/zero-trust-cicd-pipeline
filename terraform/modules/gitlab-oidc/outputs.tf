# =============================================================================
# terraform/modules/gitlab-oidc/outputs.tf
# =============================================================================

output "oidc_provider_arn" {
  description = "ARN of the AWS IAM OIDC Provider registered for GitLab."
  value       = aws_iam_openid_connect_provider.gitlab.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC Provider (https://gitlab.com)."
  value       = aws_iam_openid_connect_provider.gitlab.url
}

output "gitlab_ci_role_arn" {
  description = <<-EOT
    ARN of the IAM Role that GitLab CI assumes via AssumeRoleWithWebIdentity.
    Add this value as the AWS_ROLE_ARN CI/CD variable in your GitLab project.
    Example: arn:aws:iam::123456789012:role/zt-cicd-dev-gitlab-ci-role
  EOT
  value       = aws_iam_role.gitlab_ci.arn
}

output "gitlab_ci_role_name" {
  description = "Name of the IAM Role (without the ARN prefix)."
  value       = aws_iam_role.gitlab_ci.name
}

output "allowed_sub_claims" {
  description = <<-EOT
    List of OIDC sub claim values embedded in the Trust Policy.
    Use this output to verify that the policy matches the expected GitLab refs.
  EOT
  value       = local.allowed_sub_claims
}

output "setup_instructions" {
  description = "Post-apply instructions for configuring GitLab CI/CD."
  value       = <<-EOT
    ============================================================
    Terraform apply complete. Next steps:

    1. Copy the IAM Role ARN:
       AWS_ROLE_ARN = ${aws_iam_role.gitlab_ci.arn}

    2. Add it as a GitLab CI/CD variable:
       Project → Settings → CI/CD → Variables → Add variable
         Key:       AWS_ROLE_ARN
         Value:     ${aws_iam_role.gitlab_ci.arn}
         Protected: true  (available only on protected branches/tags)
         Masked:    true  (hidden in job logs)

    3. Make sure the pipeline job uses id_tokens:
         id_tokens:
           AWS_OIDC_TOKEN:
             aud: https://gitlab.com

    4. Re-verify the CA thumbprint if GitLab updates its TLS certificate.
    ============================================================
  EOT
}
