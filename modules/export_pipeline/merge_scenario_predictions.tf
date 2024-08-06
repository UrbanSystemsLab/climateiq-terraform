# Create a service account used by the function and Eventarc trigger
resource "google_service_account" "merge_scenario_predictions" {
  account_id   = "gcf-merge-predictions-sa"
  display_name = "Used By Merge Scenario Predictions Cloud Function"
}

# Create bucket for spatialized merged predictions output.
resource "google_storage_bucket" "spatialized_merged_predictions" {
  name     = "${var.bucket_prefix}climateiq-spatialized-merged-predictions"
  location = var.bucket_region
}

# Grant permission to invoke workflows
resource "google_project_iam_member" "merge_scenario_predictions_workflows_invoker" {
  project = data.google_project.project.id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

# Create a Cloud Workflow which watches the input bucket and triggers tasks.
resource "google_workflows_workflow" "merge_scenario_predictions" {
  name            = "merge-scenario-predictions"
  region          = var.bucket_region
  description     = "Watches climateiq-spatialized-chunk-predictions bucket for new files and triggers trigger-export-pipeline CF"
  service_account = google_service_account.merge_scenario_predictions.id
  source_contents = <<-EOF
  main:
      params: [event]
      steps:
          - init:
              assign:
                  - project_id: $${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
                  - event_bucket: $${event.data.bucket}
                  - event_file: $${event.data.name}
                  - job_name: merge-scenario-predictions
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
resource "google_project_iam_member" "merge_scenario_predictions_receiving" {
  project    = data.google_project.project.id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
  depends_on = [google_project_service.eventarc]
}

# Create an Eventarc trigger, routing Cloud Storage events to Workflows
resource "google_eventarc_trigger" "spatialized_chunk_created" {
  name     = "spatialized-chunk-created"
  location = var.bucket_region

  # Capture objects changed in the bucket
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.spatialized_chunk_predictions.name
  }

  # Send events to Workflow
  destination {
    workflow = google_workflows_workflow.merge_scenario_predictions.id
  }

  service_account = google_service_account.merge_scenario_predictions.id

  depends_on = [google_project_service.eventarc]
}

# Grant permissions needed for the Cloud Run Job to run.
resource "google_project_iam_member" "merge_scenario_predictions_invoking" {
  project    = data.google_project.project.project_id
  role       = "roles/run.developer"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

resource "google_project_iam_member" "merge_scenario_predictions_artifactregistry_reader" {
  project    = data.google_project.project.project_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.merge_scenario_predictions.email}"
}

# Give read/write access to Firestore.
resource "google_project_iam_member" "merge_scenario_predictions_firestore_user" {
  project = data.google_project.project.project_id
  role    = "roles/datastore.user"
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

# Create Cloud Run Job.
resource "google_cloud_run_v2_job" "merge_scenario_predictions" {
  name         = "merge-scenario-predictions"
  location     = var.bucket_region
  project      = data.google_project.project.project_id

  template {
    task_count = 1
    parallelism = 1

    template {
      containers {
        image = "${var.bucket_region}-docker.pkg.dev/${data.google_project.project.project_id}/cloud-run-containers/merge-scenario-predictions:latest"
        env {
          name  = "BUCKET_PREFIX"
          value = var.bucket_prefix
        }
        resources {
          limits = {
            cpu    = "8"
            memory = "32Gi"
          }
        }
      }
      timeout = "86400s"
      service_account = google_service_account.merge_scenario_predictions.email
      max_retries = 0
    }
  }
}
