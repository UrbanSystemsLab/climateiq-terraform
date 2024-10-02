# GCP Data Pipeline Deployment with Terraform

## Initial Setup
- [Install Terraform](https://developer.hashicorp.com/terraform/install)
- [Install the gcloud CLI](https://cloud.google.com/sdk/docs/install)

From the root of this repository:
```bash
git submodule init
```

From the root of this repository:
```bash
cd dev
terraform init
```

From the root of this repository:
```bash
cd prod
terraform init
```

You will need read & write permissions to the `climateiq-state` and
`test-climateiq-state` GCS buckets, as this is where
[Terraform state](https://developer.hashicorp.com/terraform/language/state)
is stored.

### Troubleshooting
#### `invalid_grant` or `reauth related error (invalid_rapt)` error
"invalid_grant" error in Terraform when trying to access your Cloud Storage backend
usually points to an issue with your authentication credentials and permissions.
To fix this, reauthenticate your Google Cloud SDK by running:
```bash
gcloud auth application-default login
```
This will open a browser window for you to log in and refresh your credentials.

## Deployment

The code for the Cloud Functions deployed by this
Terraform are in the
[climateiq-cnn](https://github.com/UrbanSystemsLab/climateiq-cnn) and
[climateiq-frontend](https://github.com/UrbanSystemsLab/climateiq-frontend)
repositories.
They are included in this Terraform repository as
[Git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules).
Before deploying, you need to get the most recent version of the code from those
repositories. To do so:

```bash
git submodule update --remote --init --recursive
```

To deploy to staging, from the root of this repository:
```bash
cd dev
terraform apply
```

To deploy to production, perform the same steps but from the `prod` directory
```bash
cd prod
terraform apply
```

## Cloud function testing

The following command is an example testing the cloud functions via HTTP request.

```sh
gcloud functions call generate-feature-matrix-http --region us-central1 --data '{ "bucket": "test-climateiq-study-area-feature-chunks/NYC_Heat", "name": "met_em.d03.2015-05-22_00:00:00.npy" }'
```
