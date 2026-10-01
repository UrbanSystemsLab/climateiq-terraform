data "google_project" "project" {
}

locals {
  h3_source_dir = "${path.module}/../../climateiq-cnn/usl_pipeline/h3_cloud_functions"

  h3_root_source_files = [
    "${local.h3_source_dir}/main.py",
    "${local.h3_source_dir}/requirements.txt",
    "${local.h3_source_dir}/cities_config.yaml",
    "${local.h3_source_dir}/cli_unified_pipeline.py",
    "${local.h3_source_dir}/cli_add_admin_breadcrumbs.py",
    "${local.h3_source_dir}/cli_preprocess_tiff_to_h3csv.py",
  ]
  h3_tools_source_files = tolist(fileset("${local.h3_source_dir}/usl_h3_tools/", "**/*.py"))
  h3_tools_dir          = "${local.h3_source_dir}/usl_h3_tools/"
}

resource "local_file" "h3_to_temp_dir_root" {
  count = length(local.h3_root_source_files)

  filename = "${path.module}/temp/${basename(element(local.h3_root_source_files, count.index))}"
  content  = sensitive(file(element(local.h3_root_source_files, count.index)))
}

resource "local_file" "h3_to_temp_dir_tools" {
  count = length(local.h3_tools_source_files)

  filename = "${path.module}/temp/usl_h3_tools/${element(local.h3_tools_source_files, count.index)}"
  content  = sensitive(file("${local.h3_tools_dir}${element(local.h3_tools_source_files, count.index)}"))
}

data "archive_file" "h3_source" {
  type        = "zip"
  output_path = "${path.module}/files/h3_cloud_function_source.zip"
  source_dir  = "${path.module}/temp"

  depends_on = [
    local_file.h3_to_temp_dir_root,
    local_file.h3_to_temp_dir_tools,
  ]
}

resource "google_storage_bucket_object" "h3_source" {
  name   = "h3_cloud_function_source.zip"
  bucket = var.source_code_bucket.name
  source = data.archive_file.h3_source.output_path
}

data "google_storage_project_service_account" "gcs" {
}

resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = data.google_project.project.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}
