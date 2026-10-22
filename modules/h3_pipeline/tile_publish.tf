locals {
  tile_publish_count = var.h3_tiles_bucket == null ? 0 : 1
}

data "google_storage_bucket" "h3_tiles" {
  count = local.tile_publish_count
  name  = var.h3_tiles_bucket
}

resource "google_project_iam_member" "h3_pipeline_workflows_invoking" {
  count   = local.tile_publish_count
  project = data.google_project.project.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_storage_bucket_iam_member" "h3_pipeline_tiles_user" {
  count  = local.tile_publish_count
  bucket = data.google_storage_bucket.h3_tiles[0].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_secret_manager_secret_iam_member" "h3_pipeline_mapbox_token_accessor" {
  count     = local.tile_publish_count
  project   = data.google_project.project.project_id
  secret_id = var.mapbox_token_secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.h3_pipeline.email}"
}

resource "google_cloudfunctions2_function" "h3_tile_publish" {
  count = local.tile_publish_count
  depends_on = [
    google_secret_manager_secret_iam_member.h3_pipeline_mapbox_token_accessor,
    google_storage_bucket_iam_member.h3_pipeline_tiles_user,
  ]

  name        = "h3-tile-publish"
  description = "Publishes H3 tiles bucket GeoJSON as Mapbox tilesets."
  location    = var.bucket_region

  build_config {
    runtime     = "python311"
    entry_point = "publish_tiles"
    source {
      storage_source {
        bucket = var.source_code_bucket.name
        object = google_storage_bucket_object.h3_source.name
      }
    }
  }

  service_config {
    available_memory      = "4Gi"
    available_cpu         = "2"
    timeout_seconds       = 3600
    service_account_email = google_service_account.h3_pipeline.email
    environment_variables = {
      BUCKET_PREFIX   = var.bucket_prefix
      GCS_BUCKET      = data.google_storage_bucket.h3_tiles[0].name
      TILE_TARGETS    = "mapbox"
      MAPBOX_USERNAME = var.mapbox_username
    }
    secret_environment_variables {
      key        = "MAPBOX_ACCESS_TOKEN"
      project_id = data.google_project.project.project_id
      secret     = var.mapbox_token_secret
      version    = "latest"
    }
  }

  lifecycle {
    ignore_changes       = [build_config[0].source]
    replace_triggered_by = [google_storage_bucket_object.h3_source]

    precondition {
      condition     = can(regex("^[A-Za-z0-9_-]+$", var.mapbox_username))
      error_message = "mapbox_username must be set to the Mapbox account that owns the token."
    }
  }
}

# Runs on each tiles bucket upload. A top-level "force": true in the execution
# argument republishes an unchanged object.
resource "google_workflows_workflow" "h3_tile_publish" {
  count           = local.tile_publish_count
  name            = "h3-tile-publish"
  region          = var.bucket_region
  description     = "Publishes a tileset when an H3 tiles bucket source is uploaded."
  service_account = google_service_account.h3_pipeline.id
  source_contents = <<-EOF
  main:
    params: [event]
    steps:
      - init:
          assign:
            - bucket: $${event.data.bucket}
            - name: $${event.data.name}
            - force: $${default(map.get(event, "force"), false)}
            - url: ${google_cloudfunctions2_function.h3_tile_publish[0].service_config[0].uri}
      - filter:
          switch:
            - condition: $${not(text.match_regex(name, "^[^/]+/(h3_[^/]+|admin)[.]geojson$"))}
              return: "ignored"
      - plan:
          call: call_publisher
          args:
            url: $${url}
            timeout: 300
            body:
              action: plan
              bucket: $${bucket}
              name: $${name}
              force: $${force}
          result: plan
      - check_plan:
          switch:
            - condition: $${plan.status != "ready"}
              return: $${plan}
      - convert:
          call: call_publisher
          args:
            url: $${url}
            timeout: 1800
            body:
              action: convert
              bucket: $${bucket}
              name: $${name}
      - upload:
          call: call_publisher
          args:
            url: $${url}
            timeout: 1800
            body:
              action: upload
              bucket: $${bucket}
              name: $${name}
      - publish:
          call: call_publisher
          args:
            url: $${url}
            timeout: 600
            body:
              action: publish
              bucket: $${bucket}
              name: $${name}
          result: published
      - done:
          return: $${published}

  call_publisher:
    params: [url, timeout, body]
    steps:
      - post:
          try:
            call: http.post
            args:
              url: $${url}
              auth:
                type: OIDC
              timeout: $${timeout}
              body: $${body}
            result: response
          retry:
            predicate: $${http.default_retry_predicate}
            max_retries: 2
            backoff:
              initial_delay: 30
              max_delay: 120
              multiplier: 2
      - done:
          return: $${response.body}
EOF
}

resource "google_eventarc_trigger" "h3_tiles_finalized" {
  count = local.tile_publish_count
  depends_on = [
    google_project_iam_member.gcs_pubsub_publishing,
    google_project_iam_member.h3_pipeline_event_receiving,
    google_project_iam_member.h3_pipeline_workflows_invoking,
  ]

  name     = "h3-tiles-finalized"
  location = lower(data.google_storage_bucket.h3_tiles[0].location)

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = data.google_storage_bucket.h3_tiles[0].name
  }

  destination {
    workflow = google_workflows_workflow.h3_tile_publish[0].id
  }

  service_account = google_service_account.h3_pipeline.id
}
