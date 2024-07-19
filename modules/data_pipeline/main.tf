data "google_project" "project" {
}

locals {
  root_source_files = [
    "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/main.py",
    "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/requirements.txt"
  ]
  wheels_source_files  = tolist(fileset("{path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/", "*.whl"))
  usl_lib_source_files = tolist(fileset("${path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/", "**/*.py"))

  wheels_dir  = "${path.module}/../../climateiq-cnn/usl_pipeline/cloud_functions/wheels/"
  usl_lib_dir = "${path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/"
}

# Process and copy files root cloud function files to temp directory.
# A `template_file` data block is used here to first process each files content
# and make it available to use elsewhere in this file. This is necessary for files
# defined in `locals` block that is not dynamically discovered (i.e. fileset()).
data "template_file" "t_file" {
  count    = length(local.root_source_files)
  template = element(local.root_source_files, count.index)
}

resource "local_file" "to_temp_dir_root" {
  count = length(local.root_source_files)

  filename = "${path.module}/temp/${basename(element(local.root_source_files, count.index))}"
  content  = sensitive(file(element(data.template_file.t_file.*.rendered, count.index)))
}

# Copy /wheels files to temp directory
resource "local_file" "to_temp_dir_wheels" {
  count = length(local.wheels_source_files)

  filename = "${path.module}/temp/wheels/${basename(element(local.wheels_source_files, count.index))}"
  # Use base64 since wheel files are binary
  content_base64 = sensitive(filebase64("${local.wheels_dir}${element(local.wheels_source_files, count.index)}"))
}

# Copy /url_lib files to temp directory
resource "local_file" "to_temp_dir_usl_lib" {
  count = length(local.usl_lib_source_files)

  filename = "${path.module}/temp/usl_lib/${element(local.usl_lib_source_files, count.index)}"
  content  = sensitive(file("${local.usl_lib_dir}${element(local.usl_lib_source_files, count.index)}"))
}

# Place the source code for the cloud function into a GCS bucket.
data "archive_file" "source" {
  type        = "zip"
  output_path = "${path.module}/files/cloud_function_source.zip"
  source_dir  = "${path.module}/temp"

  depends_on = [
    local_file.to_temp_dir_root,
    local_file.to_temp_dir_wheels,
    local_file.to_temp_dir_usl_lib,
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
