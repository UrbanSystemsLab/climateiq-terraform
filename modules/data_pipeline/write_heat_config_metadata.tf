# Bucket for WRF heat scenario configs
resource "google_storage_bucket" "wrf_heat_config" {
  name     = "${var.bucket_prefix}climateiq-atmospheric-simulation-config"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "wrf_heat_config" {
  account_id   = "gcf-wrf-heat-config-sa"
  display_name = "write-heat-config-metadata cloud function service account"
}

# Grant permissions needed to trigger and run cloud functions.
resource "google_project_iam_member" "wrf_heat_config_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.wrf_heat_config.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "wrf_heat_config_event_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.wrf_heat_config.email}"
  depends_on = [google_project_iam_member.invoking]
}

resource "google_project_iam_member" "wrf_heat_config_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.wrf_heat_config.email}"
  depends_on = [google_project_iam_member.event_receiving]
}

# Give read access to the wrf heat config bucket
resource "google_storage_bucket_iam_member" "wrf_heat_config_reader" {
  bucket = google_storage_bucket.wrf_heat_config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.wrf_heat_config.email}"
}

# Give write access to error reporter.
resource "google_project_iam_member" "wrf_heat_config_error_writer" {
  project = data.google_project.project.project_id
  role    = "roles/errorreporting.writer"
  member  = "serviceAccount:${google_service_account.wrf_heat_config.email}"
}

# Give write access to firestore.
resource "google_project_iam_member" "wrf_heat_config_firestore_writer" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.wrf_heat_config.email}"
}

# Create a function triggered by writes to the configs bucket
resource "google_cloudfunctions2_function" "write_wrf_heat_config" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "write-wrf-heat-config-metadata"
  description = "Writes WRF heat config metadata."
  location    = lower(google_storage_bucket.wrf_heat_config.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "write_heat_scenario_config_metadata"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    available_memory      = "512Mi"
    timeout_seconds       = 60
    service_account_email = google_service_account.wrf_heat_config.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.wrf_heat_config.location) # The trigger must be in the same location as the bucket
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.wrf_heat_config.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.wrf_heat_config.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.source
    ]
  }
}
