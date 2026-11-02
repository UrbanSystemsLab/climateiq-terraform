# Bucket side of tileserver-gl, which runs on GKE from k8s/h3-tileserver/.

resource "google_storage_bucket_iam_member" "tileserver_readers" {
  for_each = toset(local.tile_publish_count == 1 ? var.tileserver_readers : [])
  bucket   = data.google_storage_bucket.h3_tiles[0].name
  role     = "roles/storage.objectViewer"
  member   = each.value
}

resource "google_storage_bucket_object" "tileserver_bootstrap_config" {
  count        = local.tile_publish_count
  bucket       = data.google_storage_bucket.h3_tiles[0].name
  name         = "tileserver/releases/bootstrap-config.json"
  content      = jsonencode({ data = {} })
  content_type = "application/json"
}
