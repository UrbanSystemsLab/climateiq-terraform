variable "source_code_bucket" {
  description = "GCS bucket containing source code for all cloud functions."
  type = object({
    name     = string
    location = string
  })
}

variable "bucket_region" {
  description = "Region in which to create all GCS buckets."
  type        = string
  default     = "us-central1"
}

variable "bucket_prefix" {
  description = "Prefix to be appended to all GCS buckets."
  type        = string
}

variable "h3_pipeline_bucket" {
  description = "Name of the existing GCS bucket for H3 pipeline data and admin boundaries."
  type        = string
}

variable "predictions_bucket" {
  description = "Name of the existing GCS bucket for flood predictions (created by export_pipeline)."
  type        = string
}

variable "h3_tiles_bucket" {
  description = "Name of the existing GCS bucket whose H3 and admin GeoJSON is published as tilesets. Null disables tile publishing."
  type        = string
  default     = null
}

variable "mapbox_username" {
  description = "Mapbox account that owns the published tilesets."
  type        = string
  default     = null
}

variable "mapbox_token_secret" {
  description = "Existing Secret Manager secret holding the Mapbox access token."
  type        = string
  default     = "mapbox-access-token"
}
