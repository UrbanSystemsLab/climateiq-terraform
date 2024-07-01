# Bucket for predictions input.
resource "google_storage_bucket" "predictions" {
  name     = "${var.bucket_prefix}climateiq-predictions"
  location = var.bucket_region
}

# Bucket for split chunk predictions output.
resource "google_storage_bucket" "chunk_predictions" {
  name     = "${var.bucket_prefix}climateiq-chunk-predictions"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "trigger_export" {
  account_id   = "gcf-trigger-export-sa"
  display_name = "Used By Trigger Export Cloud Function"
}

# Grant permissions needed for the cloud function to run and receive event triggers.
resource "google_project_iam_member" "trigger_export_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "trigger_export_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
  depends_on = [google_project_iam_member.invoking]
}

resource "google_project_iam_member" "trigger_export_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
  depends_on = [google_project_iam_member.event_receiving]
}

# Give read access to the predictions bucket.
resource "google_storage_bucket_iam_member" "trigger_export_predictions_reader" {
  bucket = google_storage_bucket.predictions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Give write access to the chunk predictions bucket.
resource "google_storage_bucket_iam_member" "trigger_export_chunk_predictions_writer" {
  bucket = google_storage_bucket.chunk_predictions.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Give read access to firestore.
resource "google_project_iam_member" "trigger_export_firestore_reader" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.viewer"
  member  = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "source" {
  type        = "zip"
  output_path = "${path.module}/files/cloud_function_source.zip"

  # Add main.py to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_trigger_export_pipeline_cf/main.py")
    filename = "main.py"
  }
  # Add requirements.txt to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_trigger_export_pipeline_cf/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "source" {
  name   = basename(data.archive_file.source.output_path)
  bucket = google_storage_bucket.source.name
  source = data.archive_file.source.output_path
}

# Create a function triggered by writes to the predictions bucket.
resource "google_cloudfunctions2_function" "trigger_export_function" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "trigger-export-pipeline"
  location    = lower(google_storage_bucket.predictions.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "subscribe"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    timeout_seconds       = 540
    service_account_email = google_service_account.trigger_export.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.predictions.location) # The trigger must be in the same location as the bucket
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.trigger_export.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.predictions.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.source
    ]
  }
}