# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "export_to_aws" {
  account_id   = "gcf-aws-export-sa"
  display_name = "Used By Export To AWS Cloud Function"
}

# Grant permissions needed for the cloud function to run.
resource "google_project_iam_member" "export_to_aws_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.export_to_aws.email}"
}

resource "google_project_iam_member" "export_to_aws_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.export_to_aws.email}"
  depends_on = [google_project_service.eventarc]
}

resource "google_project_iam_member" "export_to_aws_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.export_to_aws.email}"
}

# Grant access to "climasens-aws-access-key-id" key
resource "google_secret_manager_secret_iam_member" "export_to_aws_access_access_key_id" {
  secret_id = "projects/${data.google_project.project.project_id}/secrets/climasens-aws-access-key-id"
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.export_to_aws.email}"
}

# Grant access to "climasens-aws-secret-access-key" key
resource "google_secret_manager_secret_iam_member" "export_to_aws_access_secret_access_key" {
  secret_id = "projects/${data.google_project.project.project_id}/secrets/climasens-aws-secret-access-key"
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.export_to_aws.email}"
}

# Give read/write access to the spatialized merged predictions bucket.
resource "google_storage_bucket_iam_member" "export_to_aws_spatialized_merged_predictions_user" {
  bucket = google_storage_bucket.spatialized_merged_predictions.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.export_to_aws.email}"
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "export_to_aws_source" {
  type        = "zip"
  output_path = "${path.module}/files/export_to_aws/cloud_function_source.zip"

  # Add main.py to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_export_to_aws_cf/main.py")
    filename = "main.py"
  }
  # Add requirements.txt to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_export_to_aws_cf/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "export_to_aws_source" {
  name   = "frontend_export_to_aws_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.export_to_aws_source.output_path
}

# Create a function triggered by HTTP requests.
resource "google_cloudfunctions2_function" "export_to_aws_function" {
  name        = "export-to-aws"
  location    = lower(google_storage_bucket.spatialized_chunk_predictions.location)

  build_config {
    runtime     = "python311"
    entry_point = "export_to_aws"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.export_to_aws_source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    timeout_seconds       = 3600
    service_account_email = google_service_account.export_to_aws.email
    environment_variables = {
      BUCKET_PREFIX    = var.bucket_prefix
      LOG_EXECUTION_ID = true
    }
    secret_environment_variables {
      project_id = data.google_project.project.project_id
      key     = "climasens-aws-access-key-id"
      secret  = "climasens-aws-access-key-id"
      version = "latest"
    }
    secret_environment_variables {
      project_id = data.google_project.project.project_id
      key     = "climasens-aws-secret-access-key"
      secret  = "climasens-aws-secret-access-key"
      version = "latest"
  }
    ingress_settings = "ALLOW_ALL" # Allow all traffic
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.export_to_aws_source
    ]
  }
}
