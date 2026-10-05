output "runtime_service_account_emails" {
  description = "Runtime service accounts of the pipeline Cloud Functions (the CI deployer needs actAs on each)."
  value = [
    google_service_account.generate_feature_matrix.email,
    google_service_account.rescale_feature_matrix.email,
    google_service_account.study_area_writer.email,
    google_service_account.city_cat_config.email,
    google_service_account.labels.email,
    google_service_account.wrf_labels.email,
    google_service_account.wrf_study_area_chunk_uploader.email,
    google_service_account.wrf_heat_config.email,
  ]
}
