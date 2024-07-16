# Bucket for raw WRF inputs (aka WPS "outputs")
resource "google_storage_bucket" "raw_wps_outputs" {
  name     = "${var.bucket_prefix}climateiq-atmospheric-simulation-input"
  location = var.bucket_region
}

# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "wrf_study_area_chunk_uploader" {
  account_id   = "gcf-wrf-study-uploader-sa"
  display_name = "wrf-study-area-chunk-uploader cloud function service account"
}

# Grant permissions needed to trigger and run cloud functions.
resource "google_project_iam_member" "wrf_study_area_chunk_uploader_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "wrf_study_area_chunk_uploader_event_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
  depends_on = [google_project_iam_member.invoking]
}

resource "google_project_iam_member" "wrf_study_area_chunk_uploader_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
  depends_on = [google_project_iam_member.event_receiving]
}

# Give read access to the raw_wps_outputs bucket
resource "google_storage_bucket_iam_member" "wrf_study_area_chunk_uploader_outputs_reader" {
  bucket = google_storage_bucket.raw_wps_outputs.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
}

# Give write access to the study area chunks bucket
# Study area bucket should be created in generate_feature_matrix.tf
resource "google_storage_bucket_iam_member" "wrf_study_area_chunk_uploader_chunks_writer" {
  bucket = "${var.bucket_prefix}climateiq-study-area-chunks"
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
}

# Give write access to error reporter.
resource "google_project_iam_member" "wrf_study_area_chunk_uploader_error_writer" {
  project = data.google_project.project.project_id
  role    = "roles/errorreporting.writer"
  member  = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
}

# Give write access to firestore.
resource "google_project_iam_member" "wrf_study_area_chunk_uploader_firestore_writer" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.wrf_study_area_chunk_uploader.email}"
}

# Create a function triggered by writes to the raw sim inputs bucket.
resource "google_cloudfunctions2_function" "upload_wrf_study_area_chunk" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "upload-wrf-study-area-chunk"
  description = "Uploads a raw wps file (wrf input file) as a study area chunk."
  location    = lower(google_storage_bucket.raw_wps_outputs.location) # The trigger must be in the same location as the bucket

  build_config {
    runtime     = "python311"
    entry_point = "build_and_upload_study_area_chunk"
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
    service_account_email = google_service_account.wrf_study_area_chunk_uploader.email
    environment_variables = {
      BUCKET_PREFIX = var.bucket_prefix
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.raw_wps_outputs.location) # The trigger must be in the same location as the bucket
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.wrf_study_area_chunk_uploader.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.raw_wps_outputs.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.source
    ]
  }
}
