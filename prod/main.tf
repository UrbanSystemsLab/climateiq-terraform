terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.23.0"
    }
  }
}

provider "google" {
  project = "climateiq"
}

module "data_pipeline" {
  source        = "../modules/data_pipeline"
  bucket_prefix = ""
  source_code_bucket = {
    name     = google_storage_bucket.source.name, 
    location = google_storage_bucket.source.location
  }
}

module "export_pipeline" {
  source        = "../modules/export_pipeline"
  bucket_prefix = ""
  source_code_bucket = {
    name     = google_storage_bucket.source.name, 
    location = google_storage_bucket.source.location
  }
}

resource "google_storage_bucket" "source" {
  name     = "climateiq-cloud-functions"
  location = "us-central1"
}

resource "google_storage_bucket" "tf_state" {
  name     = "climateiq-state"
  location = "us-west1"

  versioning {
    enabled = true
  }
  lifecycle {
    prevent_destroy = true
  }
}

terraform {
  backend "gcs" {
    bucket = "climateiq-state"
    prefix = "terraform/state"
  }
}
