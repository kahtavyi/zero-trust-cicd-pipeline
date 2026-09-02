# =============================================================================
# terraform/modules/gitlab-oidc/main.tf
#
# Module: AWS IAM OIDC Provider + IAM Role for GitLab CI
#
# What this module does:
#   1. Registers GitLab (https://gitlab.com) as a trusted OIDC Identity
#      Provider in AWS IAM — a one-time operation per AWS Account.
#   2. Creates an IAM Role with a Trust Policy that allows
#      AssumeRoleWithWebIdentity ONLY for the specific GitLab project
#      and branch(es) defined via input variables.
#   3. Attaches only the IAM Policies explicitly provided via var.iam_policy_arns.
#
# Security design:
#   - No wildcard '*' in Principal, Action, or Resource.
#   - `aud` is matched with StringEquals (exact value: "https://gitlab.com").
#   - `sub` is matched with StringEquals to the exact project path + branch.
#   - CA thumbprint for the GitLab OIDC endpoint is set explicitly.
# =============================================================================

# ---------------------------------------------------------------------------
# Current AWS Account ID — used to build ARNs where needed.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# AWS IAM OIDC Provider for GitLab
#
# NOTE: Only one OIDC Provider per URL can exist per AWS Account.
# If an OIDC Provider for https://gitlab.com already exists, Terraform
# will return a duplicate error. In that case, import it:
#   terraform import aws_iam_openid_connect_provider.gitlab <existing-ARN>
#
# Thumbprint: SHA-1 fingerprint of the GitLab.com root CA certificate.
# Verify the current value before a production apply:
#   openssl s_client -showcerts -connect gitlab.com:443 </dev/null 2>/dev/null \
#     | openssl x509 -noout -fingerprint -sha1 \
#     | tr -d ':' | tr 'A-F' 'a-f' | cut -d= -f2
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "gitlab" {
  url = "https://gitlab.com"

  # client_id_list maps to the `aud` claim GitLab embeds in the JWT.
  # For GitLab.com this value is always "https://gitlab.com".
  client_id_list = ["https://gitlab.com"]

  # Root CA thumbprint. Verify this value before applying to production.
  thumbprint_list = var.gitlab_oidc_thumbprints

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-gitlab-oidc-provider"
  })
}

# ---------------------------------------------------------------------------
# Locals: build the list of allowed OIDC `sub` claim values.
#
# GitLab formats the `sub` claim as:
#   project_path:<namespace>/<project>:ref_type:<branch|tag>:ref:<ref_name>
#
# Example for the main branch:
#   project_path:kahtavyi/zero-trust-cicd-pipeline:ref_type:branch:ref:main
#
# Multiple entries in var.allowed_refs produce multiple allowed values
# inside the StringEquals condition.
# ---------------------------------------------------------------------------
locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.gitlab.arn

  allowed_sub_claims = [
    for ref in var.allowed_refs :
    "project_path:${var.gitlab_project_path}:ref_type:${ref.type}:ref:${ref.name}"
  ]

  # Strip the "https://" prefix — AWS uses the bare hostname as the
  # condition key in IAM policy documents.
  oidc_provider_hostname = replace(aws_iam_openid_connect_provider.gitlab.url, "https://", "")
}

# ---------------------------------------------------------------------------
# Trust Policy — allows GitLab CI to call AssumeRoleWithWebIdentity.
#
# Constraints applied (principle of least privilege):
#   - Principal : only this specific OIDC Provider ARN (no wildcard)
#   - Action    : only sts:AssumeRoleWithWebIdentity (no sts:*)
#   - aud       : exact match "https://gitlab.com"
#   - sub       : exact match for project path + branch (StringEquals, not StringLike)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "gitlab_oidc_trust" {
  statement {
    sid     = "GitLabOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Validate the `aud` claim — GitLab always sets this to "https://gitlab.com".
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostname}:aud"
      values   = ["https://gitlab.com"]
    }

    # Validate the `sub` claim — restricts access to the exact project and
    # branch(es) listed in var.allowed_refs. StringEquals rejects any wildcard.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_hostname}:sub"
      values   = local.allowed_sub_claims
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role assumed by GitLab CI via OIDC.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "gitlab_ci" {
  name        = "${var.name_prefix}-gitlab-ci-role"
  description = "Role assumed by GitLab CI via OIDC for project ${var.gitlab_project_path}"

  assume_role_policy = data.aws_iam_policy_document.gitlab_oidc_trust.json

  # Keep the session duration at the minimum required for a typical CI job.
  # Shorter TTL reduces the blast radius if a token is ever compromised.
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, {
    Name          = "${var.name_prefix}-gitlab-ci-role"
    GitLabProject = var.gitlab_project_path
    ManagedBy     = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Attach only the IAM policies explicitly provided by the caller.
# Never attach AdministratorAccess or any wildcard-action policy here.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "gitlab_ci" {
  for_each = toset(var.iam_policy_arns)

  role       = aws_iam_role.gitlab_ci.name
  policy_arn = each.value
}
