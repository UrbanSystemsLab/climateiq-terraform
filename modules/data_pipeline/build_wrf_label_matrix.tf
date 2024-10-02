# Bucket for raw WRF simulation output.
resource "google_storage_bucket" "raw_wrf_outputs" {
  name     = "${var.bucket_prefix}climateiq-atmospheric-simulation-output"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "wrf_labels" {
  account_id   = "gcf-wrf-label-processing-sa"
  display_name = "Used By WRF Label Processing Cloud Function"
}

# Grant permissions needed for the cloud function to run and receive event triggers.
resource "google_project_iam_member" "wrf_labels_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.wrf_labels.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "wrf_labels_event_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.wrf_labels.email}"
  depends_on = [google_project_iam_member.invoking]
}

resource "google_project_iam_member" "wrf_labels_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.wrf_labels.email}"
  depends_on = [google_project_iam_member.event_receiving]
}

# Give read & write access to the raw output bucket.
resource "google_storage_bucket_iam_member" "wrf_labels_reader" {
  bucket = google_storage_bucket.raw_wrf_outputs.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.wrf_labels.email}"
}

# Give write access to the processed labels bucket.
resource "google_storage_bucket_iam_member" "wrf_processed_labels_writer" {
  bucket = "${var.bucket_prefix}climateiq-study-area-label-chunks"
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.wrf_labels.email}"
}

# Give write access to error reporter.
resource "google_project_iam_member" "wrf_labels_error_writer" {
  project = data.google_project.project.project_id
  role    = "roles/errorreporting.writer"
  member  = "serviceAccount:${google_service_account.wrf_labels.email}"
}

# Give write access to firestore.
resource "google_project_iam_member" "wrf_labels_firestore_writer" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.wrf_labels.email}"
}

# Create a function triggered by writes to the wrf outputs bucket.
resource "google_cloudfunctions2_function" "build_wrf_label_matrix" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "build-wrf-label-matrix"
  description = "Processes WRF outputs and builds wrf label matrix"
  location    = lower(google_storage_bucket.raw_wrf_outputs.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "build_wrf_label_matrix"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    timeout_seconds       = 540
    service_account_email = google_service_account.wrf_labels.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.raw_wrf_outputs.location) # The trigger must be in the same location as the bucket
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.wrf_labels.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.raw_wrf_outputs.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.source
    ]
  }
}


# Create a function triggered by writes to the wrf outputs bucket.
resource "google_cloudfunctions2_function" "build_wrf_label_matrix_http" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "build-wrf-label-matrix-http"
  description = "Processes WRF outputs and builds wrf label matrix"
  location    = lower(google_storage_bucket.raw_wrf_outputs.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "build_wrf_label_matrix_http"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    timeout_seconds       = 540
    service_account_email = google_service_account.wrf_labels.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }
}