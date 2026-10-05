output "workload_identity_provider" {
  description = "Value for the GCP_WORKLOAD_IDENTITY_PROVIDER GitHub Environment variable."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  description = "Value for the GCP_DEPLOYER_SERVICE_ACCOUNT GitHub Environment variable."
  value       = google_service_account.deployer.email
}
