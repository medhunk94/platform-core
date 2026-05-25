# Setting Up Velero Credentials

The `credentials-minio` file is required for Velero to authenticate with MinIO.

## Setup Instructions

1. Copy the example file:
   ```bash
   cp credentials-minio.example credentials-minio
   ```

2. Edit `credentials-minio` and replace the placeholder values:
   - `YOUR_MINIO_ACCESS_KEY` → your MinIO access key (default: `minio-admin`)
   - `YOUR_MINIO_SECRET_KEY` → your MinIO secret key (default: `minio-password`)

3. The file will be automatically ignored by Git (see `.gitignore`)

## For This Demo

If you're running the local MinIO setup from `helm/minio-values.yaml`, use:
```
[default]
aws_access_key_id=minio-admin
aws_secret_access_key=minio-password
```

**Note:** Never commit actual credentials to Git, even for local development.
