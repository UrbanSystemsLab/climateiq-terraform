data "google_project" "project" {
}

locals {
  source_files = concat(
    # Add paths to files from /cloud_functions's root
    [
      "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/main.py",
      "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/requirements.txt"
    ],
    # Add paths to all .py files from /usl_lib subdirectory
    tolist(fileset("${path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/", "**/*.py")),
    # Add paths to all .whl files from /cloud_functions's /wheels subdirectory
    tolist(fileset("${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/", "*.whl"))
  )

  usl_lib_dir = "${path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/"
  wheels_dir = "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/"
}

# Read and process the content from source_files
data "template_file" "t_file" {
  count = "${length(local.source_files)}"
  template = element(local.source_files, count.index)
}

# Copy files to a temporary directory to prep for zip
resource "local_file" "to_temp_dir" {
  count    = "${length(local.source_files)}"

  # Filenames are constructed to preserve source subdirectory structure within /temp
  filename = "${path.module}/temp/${
    contains(fileset(local.usl_lib_dir, "**/"), element(local.source_files, count.index)) ?        
      "usl_lib/${element(local.source_files, count.index)}" : 
    contains(fileset(local.wheels_dir, "*"), element(local.source_files, count.index)) ? 
      "wheels/${element(local.source_files, count.index)}" :
    basename(element(local.source_files, count.index))
  }"

  content  = "${element(data.template_file.t_file.*.rendered, count.index)}"
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "source" {
  type        = "zip"
  output_path = "${path.module}/files/cloud_function_source.zip"
  source_dir  = "${path.module}/temp"

  depends_on = [
    local_file.to_temp_dir,
  ]
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
