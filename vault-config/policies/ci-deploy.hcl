# Scoped policy for future GitLab CI jobs (deploy stage).
# CI can verify its own token and check Vault health — no admin access.

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "sys/health" {
  capabilities = ["read", "sudo"]
}
