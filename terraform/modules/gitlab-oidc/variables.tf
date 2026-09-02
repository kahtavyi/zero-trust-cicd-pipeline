# =============================================================================
# terraform/modules/gitlab-oidc/variables.tf
# =============================================================================

# ---------------------------------------------------------------------------
# Required variables
# ---------------------------------------------------------------------------

variable "gitlab_project_path" {
  description = <<-EOT
    Full GitLab project path in the format namespace/project-name.
    Used to construct the `sub` claim value in the IAM Trust Policy.
    Example: "kahtavyi/zero-trust-cicd-pipeline"

    Must be an exact path — no wildcards or globs allowed.
    This value determines which GitLab project can assume the role.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+/[a-zA-Z0-9._-]+$", var.gitlab_project_path))
    error_message = "gitlab_project_path must follow the format 'namespace/project-name', e.g. 'kahtavyi/zero-trust-cicd-pipeline'."
  }
}

variable "allowed_refs" {
  description = <<-EOT
    List of Git refs (branches or tags) permitted to call AssumeRoleWithWebIdentity.
    Each entry must specify a `type` ("branch" or "tag") and an exact `name`.

    Example:
    [
      { type = "branch", name = "main" }
    ]

    Security guidance:
    - Restrict to production branches only (e.g., main or master).
    - Do NOT allow ref_type:branch:ref:* — that would permit any branch.
    - Use a separate role with reduced permissions for staging environments.
  EOT
  type = list(object({
    type = string
    name = string
  }))

  validation {
    condition = alltrue([
      for ref in var.allowed_refs :
      contains(["branch", "tag"], ref.type) && length(ref.name) > 0 && !contains(["*", "?"], tolist(split("", ref.name)))
    ])
    error_message = "Each ref must have type 'branch' or 'tag', a non-empty name, and must not contain wildcard characters (* or ?)."
  }
}

variable "name_prefix" {
  description = <<-EOT
    Prefix applied to all AWS resource names created by this module.
    Example: "zt-cicd-dev" produces "zt-cicd-dev-gitlab-ci-role".
    Include the project name and environment to keep names unique.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must start with a letter, contain only a-z, A-Z, 0-9, '-', and be no longer than 32 characters."
  }
}

# ---------------------------------------------------------------------------
# Optional variables with defaults
# ---------------------------------------------------------------------------

variable "gitlab_oidc_thumbprints" {
  description = <<-EOT
    SHA-1 thumbprint(s) of the root CA certificate for the GitLab OIDC endpoint.

    Verify the current value before applying to production:
      openssl s_client -showcerts -connect gitlab.com:443 </dev/null 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha1 \
        | tr -d ':' | tr 'A-F' 'a-f' | cut -d= -f2

    AWS uses this thumbprint to identify the CA, but performs JWT signature
    verification using the public keys from GitLab's JWKS endpoint.
    Update this value if GitLab rotates its TLS certificate.
  EOT
  type        = list(string)
  default     = ["b3dd7606d2b5a8b4a13771dbecc9ee1cecafa38a"]

  validation {
    condition     = length(var.gitlab_oidc_thumbprints) > 0
    error_message = "At least one thumbprint must be provided."
  }
}

variable "max_session_duration" {
  description = <<-EOT
    Maximum STS session duration in seconds.
    Allowed range: 3600 (1 hour) to 43200 (12 hours).
    Recommended: 3600 — sufficient for most CI jobs.
    A shorter TTL limits the blast radius in the event of token compromise.
  EOT
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "iam_policy_arns" {
  description = <<-EOT
    List of IAM Policy ARNs to attach to the GitLab CI Role.
    Follow the principle of least privilege — attach only what the job actually needs.

    Examples:
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
      "arn:aws:iam::123456789012:policy/MyCustomDeployPolicy"

    AdministratorAccess and PowerUserAccess are explicitly rejected
    by the validation rule below.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.iam_policy_arns :
      can(regex("^arn:aws:iam::", arn)) &&
      !can(regex("AdministratorAccess|PowerUserAccess", arn))
    ])
    error_message = "All ARNs must start with 'arn:aws:iam::'. AdministratorAccess and PowerUserAccess are not allowed."
  }
}

variable "tags" {
  description = <<-EOT
    Additional AWS tags applied to all resources created by this module.
    Recommended keys: Environment, Owner, CostCenter, Project.
    Example: { Environment = "dev", Owner = "kahtavyi" }
  EOT
  type        = map(string)
  default     = {}
}
