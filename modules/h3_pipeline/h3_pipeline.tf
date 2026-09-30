resource "google_storage_bucket" "h3_pipeline" {
  name     = "${var.bucket_prefix}climateiq-h3-pipeline"
  location = var.bucket_region
}

resource "google_storage_bucket" "predictions" {
  name     = "${var.bucket_prefix}climateiq-predictions"
  location = var.bucket_region
}

resource "google_service_account" "h3_pipeline" {
  account_id   = "gcf-h3-pipeline-sa"
  display_name = "H3 Pipeline cloud function service account"
}

resource "google_project_iam_member" "h3_pipeline_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.h3_pipeline.email}"
  depends_on = [google_project_iam_member.gcs_pubsub_publishing]
}

resource "google_project_iam_member" "h3_pipeline_event_receiving" {
  project    = data.google_project.project.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.h3_pipeline.email}"
  depends_on = [google_project_iam_member.h3_pipeline_invoking]
}

resource "google_project_iam_member" "h3_pipeline_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.h3_pipeline.email}"
  depends_on = [google_project_iam_member.h3_pipeline_event_receiving]
}

resource "google_project_iam_member" "h3_pipeline_error_writer" {
  project = data.google_project.project.project_id
  role    = "roles/errorreporting.writer"
  member  = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_storage_bucket_iam_member" "h3_pipeline_bucket_user" {
  bucket = google_storage_bucket.h3_pipeline.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_storage_bucket_iam_member" "h3_pipeline_predictions_reader" {
  bucket = google_storage_bucket.predictions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_cloudfunctions2_function" "h3_pipeline" {
  name        = "h3-pipeline"
  description = "H3 Admin Hex Pipeline: processes flood predictions into H3 tilesets with admin boundaries."
  location    = var.bucket_region

  build_config {
    runtime     = "python311"
    entry_point = "process_h3_pipeline"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.h3_source.name
      }
    }
  }

  service_config {
    available_memory      = "32Gi"
    available_cpu         = "8"
    timeout_seconds       = 3600
    service_account_email = google_service_account.h3_pipeline.email
    environment_variables = {
      GCS_BUCKET = google_storage_bucket.h3_pipeline.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.h3_source
    ]
  }
}

resource "google_cloudfunctions2_function" "h3_pipeline_tiff_trigger" {
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
  ]

  name        = "h3-pipeline-tiff-trigger"
  description = "Triggers H3 pipeline when flood prediction mosaic TIFs are uploaded."
  location    = lower(google_storage_bucket.predictions.location)

  build_config {
    runtime     = "python311"
    entry_point = "process_h3_pipeline_on_tiff_upload"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.h3_source.name
      }
    }
  }

  service_config {
    available_memory      = "32Gi"
    available_cpu         = "8"
    timeout_seconds       = 3600
    service_account_email = google_service_account.h3_pipeline.email
    environment_variables = {
      GCS_BUCKET = google_storage_bucket.h3_pipeline.name
    }
  }

  event_trigger {
    trigger_region        = lower(google_storage_bucket.predictions.location)
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.h3_pipeline.email
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.predictions.name
    }
  }

  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.h3_source
    ]
  }
}
