# =============================================================================
# terraform/environments/dev/variables.tf
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "gitlab_project_path" {
  description = <<-EOT
    Full GitLab project path (namespace/project).
    Embedded in the OIDC sub claim inside the IAM Trust Policy.
  EOT
  type    = string
  default = "kahtavyi/zero-trust-cicd-pipeline"
}

variable "allowed_refs" {
  description = "Git refs allowed to call AssumeRoleWithWebIdentity."
  type = list(object({
    type = string
    name = string
  }))
  default = [
    { type = "branch", name = "main" }
  ]
}

variable "name_prefix" {
  description = "Prefix applied to all AWS resource names."
  type        = string
  default     = "zt-cicd-dev"
}

variable "iam_policy_arns" {
  description = <<-EOT
    IAM Policy ARNs to attach to the GitLab CI Role.
    ReadOnlyAccess is the safest starting point for a demo.
    Replace with a custom least-privilege policy for real workloads.
  EOT
  type        = list(string)
  default = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]
}

variable "max_session_duration" {
  description = "Maximum STS session duration in seconds (3600 = 1 hour)."
  type        = number
  default     = 3600
}

variable "owner" {
  description = "Owner name or handle — used in resource tags."
  type        = string
  default     = "kahtavyi"
}

variable "extra_tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
