# Create bucket for spatialized merged predictions output.
resource "google_storage_bucket" "spatialized_merged_predictions" {
  name     = "${var.bucket_prefix}climateiq-spatialized-merged-predictions"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "merge_scenario_predictions" {
  account_id   = "gcf-merge-predictions-sa"
  display_name = "Used By Merge Scenario Predictions Cloud Function"
}

# Grant permissions needed for the cloud function to run and receive event triggers.
resource "google_project_iam_member" "merge_scenario_predictions_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "merge_scenario_predictions_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
  depends_on = [google_project_iam_member.merge_scenario_predictions_invoking]
}

resource "google_project_iam_member" "merge_scenario_predictions_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
  depends_on = [google_project_iam_member.merge_scenario_predictions_receiving]
}

# Give read access to Firestore.
resource "google_project_iam_member" "merge_scenario_predictions_firestore_reader" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.viewer"
  member = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

# Give read access to the spatialized chunk predictions bucket.
resource "google_storage_bucket_iam_member" "merge_scenario_predictions_spatialized_chunk_predictions_reader" {
  bucket = google_storage_bucket.spatialized_chunk_predictions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

# Give write access to the spatialized merged predictions bucket.
resource "google_storage_bucket_iam_member" "merge_scenario_predictions_spatialized_merged_predictions_writer" {
  bucket = google_storage_bucket.spatialized_merged_predictions.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "merge_scenario_predictions_source" {
  type        = "zip"
  output_path = "${path.module}/files/merge_scenario_predictions/cloud_function_source.zip"

  # Add main.py to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_merge_scenario_predictions_cf/main.py")
    filename = "main.py"
  }
  # Add requirements.txt to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-frontend/cloud_functions/climateiq_merge_scenario_predictions_cf/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "merge_scenario_predictions_source" {
  name   = "frontend_merge_scenario_predictions_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.merge_scenario_predictions_source.output_path
}

# Create a function triggered by writes to the spatialized chunk predictions bucket.
resource "google_cloudfunctions2_function" "merge_scenario_predictions_function" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "merge-scenario-predictions"
  location    = lower(google_storage_bucket.spatialized_chunk_predictions.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "merge_scenario_predictions"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.merge_scenario_predictions_source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    timeout_seconds       = 540
    service_account_email = google_service_account.merge_scenario_predictions.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.spatialized_chunk_predictions.location) # The trigger must be in the same location as the bucket
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.merge_scenario_predictions.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.spatialized_chunk_predictions.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.merge_scenario_predictions_source
    ]
  }
}
