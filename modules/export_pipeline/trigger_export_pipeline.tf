# Create a service account used by the Job and Eventarc trigger
resource "google_service_account" "trigger_export" {
  account_id   = "gcf-trigger-export-sa"
  display_name = "Used By Trigger Export Cloud Run Job"
}

# Create bucket for predictions input.
resource "google_storage_bucket" "predictions" {
  name     = "${var.bucket_prefix}climateiq-predictions"
  location = var.bucket_region
}

# Create bucket for split chunk predictions output.
resource "google_storage_bucket" "chunk_predictions" {
  name     = "${var.bucket_prefix}climateiq-chunk-predictions"
  location = var.bucket_region
}

# Grant permission to invoke workflows
resource "google_project_iam_member" "trigger_export_workflows_invoker" {
  project = data.google_project.project.id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Create a Cloud Workflow which watches the input bucket and triggers tasks.
resource "google_workflows_workflow" "trigger_export_pipeline" {
  name            = "trigger-export-pipeline"
  region          = var.bucket_region
  description     = "Watches climateiq-predictions bucket for new files and triggers trigger-export-pipeline CF"
  service_account = google_service_account.trigger_export.id
  source_contents = <<-EOF
  main:
      params: [event]
      steps:
          - init:
              assign:
                  - project_id: $${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
                  - event_bucket: $${event.data.bucket}
                  - event_file: $${event.data.name}
                  - job_name: trigger-export-pipeline
                  - job_location: ${var.bucket_region}
          - run_job:
              call: googleapis.run.v1.namespaces.jobs.run
              args:
                  name: $${"namespaces/" + project_id + "/jobs/" + job_name}
                  location: $${job_location}
                  body:
                      overrides:
                          containerOverrides:
                              args: ["python3", "main.py", '$${event_file}']
              result: job_execution
          - finish:
              return: $${job_execution}
EOF

  depends_on = [google_project_service.workflows]
}

# Grant permission to receive events
resource "google_project_iam_member" "trigger_export_event_receiver" {
  project    = data.google_project.project.id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
  depends_on = [google_project_service.eventarc]
}

# Create an Eventarc trigger, routing Cloud Storage events to Workflows
resource "google_eventarc_trigger" "prediction_file_created" {
  name     = "prediction-file-created"
  location = var.bucket_region

  # Capture objects changed in the bucket
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.predictions.name
  }

  # Send events to Workflow
  destination {
    workflow = google_workflows_workflow.trigger_export_pipeline.id
  }

  service_account = google_service_account.trigger_export.id

  depends_on = [google_project_service.eventarc]
}

# Grant permissions needed for the Cloud Run Job to run.
resource "google_project_iam_member" "trigger_export_run_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.developer"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
}

resource "google_project_iam_member" "trigger_export_run_viewing" {
  project    = data.google_project.project.project_id
  role       = "roles/run.viewer"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
}

resource "google_project_iam_member" "trigger_export_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
}

resource "google_project_iam_member" "trigger_export_enqueuing" {
  project    = data.google_project.project.project_id
  role       = "roles/cloudtasks.enqueuer"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
}

resource "google_service_account_iam_member" "trigger_export_run_as" {
  role       = "roles/iam.serviceAccountUser"
  member     = "serviceAccount:${google_service_account.trigger_export.email}"
  service_account_id = google_service_account.spatialize_chunk_predictions.name
}

# Give read access to the predictions bucket.
resource "google_storage_bucket_iam_member" "trigger_export_predictions_reader" {
  bucket = google_storage_bucket.predictions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Give write access to the chunked predictions bucket.
resource "google_storage_bucket_iam_member" "trigger_export_chunk_predictions_writer" {
  bucket = google_storage_bucket.chunk_predictions.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.trigger_export.email}"
}

# Create Cloud Run Job.
resource "google_cloud_run_v2_job" "trigger_export_pipeline" {
  name         = "trigger-export-pipeline"
  location     = var.bucket_region
  project      = data.google_project.project.project_id

  template {
    task_count = 1
    parallelism = 1

    template {
      containers {
        image = "${var.bucket_region}-docker.pkg.dev/${data.google_project.project.project_id}/cloud-run-containers/trigger-export-pipeline:latest"
        env {
          name  = "BUCKET_PREFIX"
          value = var.bucket_prefix
        }
        resources {
          limits = {
            cpu    = "1"
            memory = "4Gi"
          }
        }
      }
      timeout = "86400s"
      service_account = google_service_account.trigger_export.email
      max_retries = 0
    }
  }
}

# Create Task Queue
resource "google_cloud_tasks_queue" "spatialize_chunk_predictions_queue" {
  name = "spatialize-chunk-predictions-q"
  location = var.bucket_region

  rate_limits {
    max_concurrent_dispatches = 25
    max_dispatches_per_second = 1
  }

  retry_config {
    max_attempts = 9
    max_backoff = "3600s"
    min_backoff = "90s"
    max_doublings = 16
  }
}
