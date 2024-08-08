# Create bucket for spatialized chunk predictions output.
resource "google_storage_bucket" "spatialized_chunk_predictions" {
  name     = "${var.bucket_prefix}climateiq-spatialized-chunk-predictions"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "spatialize_chunk_predictions" {
  account_id   = "gcf-spatialize-predictions-sa"
  display_name = "Used By Spatialize Chunk Predictions Cloud Function"
}

# Grant permissions needed for the cloud function to run and receive event triggers.
resource "google_project_iam_member" "spatialize_chunk_predictions_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

resource "google_project_iam_member" "spatialize_chunk_predictions_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

resource "google_project_iam_member" "spatialize_chunk_predictions_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

# Give read access to Firestore.
resource "google_project_iam_member" "spatialize_chunk_predictions_firestore_reader" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.viewer"
  member = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

# Give read access to the chunk predictions bucket.
resource "google_storage_bucket_iam_member" "spatialize_chunk_predictions_chunk_predictions_reader" {
  bucket = google_storage_bucket.chunk_predictions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

# Give write access to the spatialized chunk predictions bucket.
resource "google_storage_bucket_iam_member" "spatialize_chunk_predictions_spatialized_chunk_predictions_writer" {
  bucket = google_storage_bucket.spatialized_chunk_predictions.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.spatialize_chunk_predictions.email}"
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "spatialize_chunk_predictions_source" {
  type        = "zip"
  output_path = "${path.module}/files/spatialize_chunk_predictions/cloud_function_source.zip"

  # Add main.py to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_spatialize_chunk_predictions_cf/main.py")
    filename = "main.py"
  }
  # Add requirements.txt to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_spatialize_chunk_predictions_cf/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "spatialize_chunk_predictions_source" {
  name   = "frontend_spatialize_chunk_predictions_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.spatialize_chunk_predictions_source.output_path
}

# Create a function triggered by messages published to the "export_predictions_topic"
resource "google_cloudfunctions2_function" "spatialize_chunk_predictions_function" {
  name        = "spatialize-chunk-predictions"
  location    = lower(google_storage_bucket.predictions.location)

  build_config {
    runtime     = "python311"
    entry_point = "spatialize_chunk_predictions"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.spatialize_chunk_predictions_source.name
      }
    }
  }

  service_config {
    available_memory   = "32Gi"
    timeout_seconds    = 1795
    max_instance_count = 50
    service_account_email = google_service_account.spatialize_chunk_predictions.email
    environment_variables = {
      BUCKET_PREFIX    = var.bucket_prefix
      LOG_EXECUTION_ID = true
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.spatialize_chunk_predictions_source
    ]
  }
}
