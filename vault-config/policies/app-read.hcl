# Least-privilege policy for the FastAPI application.
# Allows ONLY reading dynamic database credentials — nothing else.

path "database/creds/app-role" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
