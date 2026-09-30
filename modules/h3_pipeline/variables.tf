variable "source_code_bucket" {
  description = "GCS bucket containing source code for all cloud functions."
  type = object({
    name     = string
    location = string
  })
}

variable "bucket_prefix" {
  description = "Prefix to be appended to all GCS buckets."
  type        = string
}

variable "bucket_region" {
  description = "Region in which to create all GCS buckets."
  type        = string
  default     = "us-central1"
}

variable "h3_pipeline_bucket" {
  description = "Name of the existing GCS bucket for H3 pipeline data."
  type        = string
}

variable "predictions_bucket" {
  description = "Name of the existing GCS bucket for flood predictions."
  type        = string
}
