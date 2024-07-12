data "google_project" "project" {
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "source" {
  type        = "zip"
  output_path = "${path.module}/files/cloud_function_source.zip"

  # Add main.py to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/main.py")
    filename = "main.py"
  }
  # Add all the contents of cloud_functions/wheels to a /wheels directory inside the zip file.
  # Currently, we have only one wheel (for wrf-python) - to future proof in case we introduce
  # more wheels, we'll import the files in a for loop
  dynamic "source" {
    for_each = fileset("{path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/", "*.whl")
    content {
      content  = filebase64("{path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/${source.value}")
      filename = "wheels/${source.value}"
    }
  }
  # Add requirements.txt to the root of the zip file.
  source {
    content  = file("{path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/requirements.txt")
    filename = "requirements.txt"
  }
  # Add all the contents of usl_lib to a usl_lib directory inside the zip file.
  dynamic "source" {
    for_each = fileset("{path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/", "**/*.py")
    content {
      content  = file("{path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/${source.value}")
      filename = "usl_lib/${source.value}"
    }
  }
}

resource "google_storage_bucket_object" "source" {
  name   = "cnn_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.source.output_path
}

# Create a firestore database to use as our metastore.
# We only need one database, so we name it (default) as recommended:
# https://firebase.google.com/docs/firestore/manage-databases#the_default_database
resource "google_firestore_database" "database" {
  name        = "(default)"
  location_id = var.bucket_region
  type        = "FIRESTORE_NATIVE"
}

# To use GCS CloudEvent triggers, the GCS service account requires the Pub/Sub
# Publisher(roles/pubsub.publisher) IAM role in the specified project.
# (See https://cloud.google.com/eventarc/docs/run/quickstart-storage#before-you-begin)
data "google_storage_project_service_account" "gcs" {
}

resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}
