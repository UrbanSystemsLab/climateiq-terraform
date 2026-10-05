variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to deploy via Workload Identity Federation."
  type        = string
  default     = "UrbanSystemsLab/climateiq-cnn"
}

variable "allowed_refs" {
  description = "If non-empty, only tokens for these git refs may authenticate (prod: [\"refs/heads/release\"]). Leave empty in dev so any branch can be deployed manually."
  type        = list(string)
  default     = []
}

variable "runtime_service_accounts" {
  description = "Emails of the Cloud Functions runtime service accounts the deployer must be able to act as."
  type        = list(string)
}

variable "extra_act_as_service_accounts" {
  description = "Additional service account emails the deployer may act as (e.g. the add-area Cloud Run job's SA)."
  type        = list(string)
  default     = []
}
