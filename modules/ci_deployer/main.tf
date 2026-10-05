# Keyless deploy access for climateiq-cnn GitHub Actions.
#
# GitHub's OIDC token is exchanged (Workload Identity Federation) for the
# github-deployer service account, which may update Cloud Functions source,
# push images and update the add-area Cloud Run job. It cannot create
# functions, change IAM or touch buckets: terraform keeps owning those.

data "google_project" "project" {
}

resource "google_project_service" "wif" {
  for_each = toset([
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.wif]
}

locals {
  repo_condition = "assertion.repository == '${var.github_repository}'"
  ref_condition  = length(var.allowed_refs) == 0 ? "" : " && assertion.ref in ${jsonencode(var.allowed_refs)}"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "${local.repo_condition}${local.ref_condition}"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions deployer (${var.github_repository})"
}

# Let workflows from the repository impersonate the deployer.
resource "google_service_account_iam_member" "wif_user" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "deployer" {
  for_each = toset([
    "roles/cloudfunctions.developer",          # gcloud functions deploy
    "roles/run.developer",                     # gcloud run jobs update
    "roles/artifactregistry.writer",           # docker push
    "roles/serviceusage.serviceUsageConsumer", # use the project as quota project
  ])
  project = data.google_project.project.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Deploying a function or updating a job requires actAs on its runtime SA.
resource "google_service_account_iam_member" "act_as" {
  for_each           = toset(concat(var.runtime_service_accounts, var.extra_act_as_service_accounts))
  service_account_id = "projects/${data.google_project.project.project_id}/serviceAccounts/${each.key}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
