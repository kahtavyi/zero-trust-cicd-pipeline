# Least-privilege policy for the FastAPI application.
# Allows ONLY reading dynamic database credentials — nothing else.

path "database/creds/app-role" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allows the app to revoke its short-lived database lease during shutdown.
# Vault requires explicit update access to the lease-revocation endpoint.
path "sys/leases/revoke" {
  capabilities = ["update"]
}
