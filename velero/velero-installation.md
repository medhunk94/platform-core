
## Installation

There are two parts to installing Velero: the CLI on your local machine, and the server-side components inside the cluster. You also need an object storage bucket ready before you start.

### Prerequisites

- A running Kubernetes cluster (1.16+)
- `kubectl` configured and pointing at the right cluster
- An Azure subscription with an Azure Blob Storage account and container created
- Azure CLI (`az`) installed and logged in
- A Service Principal or Managed Identity with access to the storage account

---

### Step 1 — Install the Velero CLI

The CLI is how you interact with Velero from your terminal. Install it on your local machine or your CI runner.

**macOS (Homebrew)**
```bash
brew install velero
```

**Linux**
```bash
# Replace the version with the latest from https://github.com/vmware-tanzu/velero/releases
VELERO_VERSION=v1.13.2

curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz \
  | tar -xz

sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
```

Verify it worked:
```bash
velero version --client-only
```

---

### Step 2 — Create an Azure Blob Storage container

Velero needs a dedicated container to store backups. Do not reuse one that already has other data in it.

```bash
# Set these to match your environment
RESOURCE_GROUP=my-cluster-rg
STORAGE_ACCOUNT=myclustervelero        # must be globally unique, lowercase, 3-24 chars
BLOB_CONTAINER=velero-backups
LOCATION=westeurope

# Create a storage account (use Standard_GRS for geo-redundancy)
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --kind StorageV2 \
  --sku Standard_GRS

# Create the container inside the storage account
az storage container create \
  --name $BLOB_CONTAINER \
  --account-name $STORAGE_ACCOUNT
```

Enable soft delete on blobs so backups cannot be silently overwritten or removed:
```bash
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-delete-retention true \
  --delete-retention-days 30
```

---

### Step 3 — Set up credentials

Velero needs a Service Principal with access to the storage account and the ability to snapshot Azure Managed Disks. Never give Velero owner or contributor at the subscription level — scope it down.

**Create a Service Principal for Velero**
```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP=my-cluster-rg
STORAGE_ACCOUNT=myclustervelero

# Create the service principal scoped to the resource group only
SP=$(az ad sp create-for-rbac \
  --name velero-backup-sp \
  --role Contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP \
  --query '{clientId:appId, clientSecret:password, tenantId:tenant}' \
  -o json)

CLIENT_ID=$(echo $SP | jq -r .clientId)
CLIENT_SECRET=$(echo $SP | jq -r .clientSecret)
TENANT_ID=$(echo $SP | jq -r .tenantId)
```

Write the credentials to a file that `velero install` will use. This file stays on your local machine and is not committed to Git.
```bash
cat > /tmp/credentials-velero <<EOF
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
TENANT_ID=${TENANT_ID}
CLIENT_ID=${CLIENT_ID}
CLIENT_SECRET=${CLIENT_SECRET}
RESOURCE_GROUP=${RESOURCE_GROUP}
CLOUD_NAME=AzurePublicCloud
EOF
```

> If your cluster uses AKS with Managed Identity (Workload Identity), you can skip the Service Principal and configure Velero to use the node pool's managed identity instead. That is the preferred approach for production AKS clusters.

---

### Step 4 — Install Velero into the cluster

#### Option A: Using the Velero CLI (quickest for getting started)

```bash
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.9.2 \
  --bucket velero-backups \
  --backup-location-config storageAccount=myclustervelero,resourceGroup=my-cluster-rg \
  --snapshot-location-config apiTimeout=5m,resourceGroup=my-cluster-rg,subscriptionId=<SUBSCRIPTION_ID> \
  --secret-file /tmp/credentials-velero \
  --use-node-agent \
  --namespace velero
```

What these flags mean:
- `--provider azure` — tells Velero to use the Azure plugin
- `--plugins` — the Azure-specific plugin image
- `--bucket` — the blob container name you created in step 2
- `--backup-location-config` — points Velero at your storage account and resource group
- `--snapshot-location-config` — tells Velero where to create Azure Managed Disk snapshots
- `--use-node-agent` — deploys a DaemonSet for volume backup on workloads that cannot use CSI snapshots
- `--namespace velero` — installs everything into a dedicated namespace (recommended)

#### Option B: Using Helm (recommended for platform teams)

Helm gives you a repeatable, GitOps-friendly installation that you can track in version control.

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
```

Create a values file:
```yaml
# velero-values.yaml
configuration:
  backupStorageLocation:
    - name: default
      provider: azure
      bucket: velero-backups           # blob container name
      config:
        storageAccount: myclustervelero
        resourceGroup: my-cluster-rg
        storageAccountKeyEnvVar: AZURE_STORAGE_ACCOUNT_ACCESS_KEY  # optional; omit if using SP auth

  volumeSnapshotLocation:
    - name: default
      provider: azure
      config:
        apiTimeout: 5m
        resourceGroup: my-cluster-rg
        subscriptionId: <SUBSCRIPTION_ID>

credentials:
  useSecret: true
  secretContents:
    cloud: |
      AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
      AZURE_TENANT_ID=<TENANT_ID>
      AZURE_CLIENT_ID=<CLIENT_ID>
      AZURE_CLIENT_SECRET=<CLIENT_SECRET>
      AZURE_RESOURCE_GROUP=my-cluster-rg
      AZURE_CLOUD_NAME=AzurePublicCloud

initContainers:
  - name: velero-plugin-for-microsoft-azure
    image: velero/velero-plugin-for-microsoft-azure:v1.9.2
    volumeMounts:
      - mountPath: /target
        name: plugins

nodeAgent:
  enabled: true

deployNodeAgent: true
```

Install:
```bash
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values velero-values.yaml
```

Upgrade later:
```bash
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --values velero-values.yaml
```

---

### Step 5 — Verify the installation

Check that the Velero pods are running:
```bash
kubectl get pods -n velero
```

You should see something like:
```
NAME                      READY   STATUS    RESTARTS   AGE
velero-7d9f8b6c4d-xk2p9   1/1     Running   0          2m
node-agent-abc12           1/1     Running   0          2m
node-agent-def34           1/1     Running   0          2m
```

Check that the backup storage location is available (this confirms Velero can reach your bucket):
```bash
velero backup-location get
```

Expected output:
```
NAME      PROVIDER   BUCKET/PREFIX      PHASE       LAST VALIDATED   ACCESS MODE   DEFAULT
default   azure      velero-backups     Available   10s              ReadWrite     true
```

If the phase shows `Unavailable`, the credentials or bucket configuration are wrong. Check the Velero pod logs:
```bash
kubectl logs deployment/velero -n velero
```

---

### Step 6 — Run your first backup

Once the installation is verified, take a manual backup to confirm everything works end to end:
```bash
velero backup create first-backup --include-cluster-resources=true
```

Watch its progress:
```bash
velero backup describe first-backup --details
```

When the status shows `Completed`, your Velero setup is working. Now set up a schedule so backups happen automatically:
```bash
velero schedule create nightly-full \
  --schedule="0 2 * * *" \
  --include-cluster-resources=true \
  --ttl 720h
```

---

### Other provider plugin images

This guide covers Azure. If you need to support another cloud, swap the plugin image and credentials format:

| Cloud | Plugin image |
|---|---|
| Azure | `velero/velero-plugin-for-microsoft-azure:v1.9.2` |
| AWS / MinIO | `velero/velero-plugin-for-aws:v1.9.2` |
| Google Cloud | `velero/velero-plugin-for-gcp:v1.9.2` |
| CSI (generic) | `velero/velero-plugin-for-csi:v0.7.1` |

For AKS with Workload Identity (no Service Principal), add the following annotation to the Velero service account so it can pick up the federated identity:
```yaml
serviceAccount:
  server:
    annotations:
      azure.workload.identity/client-id: <MANAGED_IDENTITY_CLIENT_ID>
```

And set `AZURE_CLIENT_ID` in the credentials secret to match the managed identity client ID. Remove `AZURE_CLIENT_SECRET` entirely — it is not needed with Workload Identity.

---
