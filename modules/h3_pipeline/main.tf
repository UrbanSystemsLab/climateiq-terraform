data "google_project" "project" {
}

locals {
  h3_source_dir  = "${path.module}/../../climateiq-cnn/usl_pipeline/4_postprocessing"
  h3_package_dir = "${local.h3_source_dir}/postprocessing/"
  usl_lib_dir    = "${path.module}/../../climateiq-cnn/usl_pipeline/usl_lib/usl_lib/"

  h3_root_source_files = [
    "${local.h3_source_dir}/main.py",
    "${local.h3_source_dir}/requirements.txt",
    "${local.h3_source_dir}/cities_config.yaml",
  ]
  h3_package_source_files = tolist(fileset(local.h3_package_dir, "**/*.py"))
  usl_lib_source_files    = tolist(fileset(local.usl_lib_dir, "**/*.py"))
}

resource "local_file" "h3_to_temp_dir_root" {
  count = length(local.h3_root_source_files)

  filename = "${path.module}/temp/${basename(element(local.h3_root_source_files, count.index))}"
  content  = sensitive(file(element(local.h3_root_source_files, count.index)))
}

resource "local_file" "h3_to_temp_dir_package" {
  count = length(local.h3_package_source_files)

  filename = "${path.module}/temp/postprocessing/${element(local.h3_package_source_files, count.index)}"
  content  = sensitive(file("${local.h3_package_dir}${element(local.h3_package_source_files, count.index)}"))
}

resource "local_file" "h3_to_temp_dir_usl_lib" {
  count = length(local.usl_lib_source_files)

  filename = "${path.module}/temp/usl_lib/${element(local.usl_lib_source_files, count.index)}"
  content  = sensitive(file("${local.usl_lib_dir}${element(local.usl_lib_source_files, count.index)}"))
}

data "archive_file" "h3_source" {
  type        = "zip"
  output_path = "${path.module}/files/h3_cloud_function_source.zip"
  source_dir  = "${path.module}/temp"

  depends_on = [
    local_file.h3_to_temp_dir_root,
    local_file.h3_to_temp_dir_package,
    local_file.h3_to_temp_dir_usl_lib,
  ]
}

resource "google_storage_bucket_object" "h3_source" {
  name   = "h3_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.h3_source.output_path

  lifecycle {
    precondition {
      condition     = alltrue([for files in [local.h3_package_source_files, local.usl_lib_source_files] : length(files) > 0])
      error_message = "A source glob matched no files. Check the climateiq-cnn paths."
    }
  }
}

data "google_storage_project_service_account" "gcs" {
}

resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}
