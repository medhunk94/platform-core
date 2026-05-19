
## Use cases

### 1. Disaster recovery

This is the primary use case. You schedule nightly backups of the entire cluster and keep them for 30 days. If the cluster is lost — whether from a region failure, a catastrophic misconfiguration, or something else — you restore to a new cluster from the latest backup.

```yaml
schedule: "0 2 * * *"
includedNamespaces:
  - "*"
storageLocation: production-s3-bucket
ttl: 720h
```

### 2. Recovering from accidental deletion

Someone deletes a namespace. Or a Helm release gets uninstalled with `--purge`. With Velero you can restore just that namespace from the most recent backup, without touching anything else in the cluster.

```bash
velero restore create --from-backup nightly-backup-20260519 \
  --include-namespaces payments-service
```

### 3. Pre-upgrade safety net

Before any risky operation — Kubernetes version upgrade, storage class migration, CNI change — take a manual backup. If the upgrade goes sideways, you have a clean restore point.

```bash
velero backup create pre-upgrade-20260519 --include-cluster-resources=true
```

### 4. Cluster migration

Backing up from cluster A and restoring to cluster B is how you move workloads between clusters. This works across cloud providers, Kubernetes versions, and regions.

```bash
# On the source cluster
velero backup create full-cluster-migration

# On the target cluster (pointing to the same storage bucket)
velero restore create --from-backup full-cluster-migration
```

### 5. Cloning environments

Need a copy of staging to debug a production issue in an isolated environment? Back up the staging namespace and restore it into a dev namespace.

```bash
velero backup create staging-snapshot --include-namespaces staging

velero restore create --from-backup staging-snapshot \
  --namespace-mappings staging:dev-debug
```

### 6. Stateful application backup (databases, file stores)

If you run PostgreSQL, MySQL, MongoDB, or any other stateful workload in-cluster using PVCs, Velero captures the volume snapshot alongside the Kubernetes objects. This means your database data and its configuration are backed up and restored together consistently.

---

## Velero vs other approaches

| Approach | What it covers | What it misses |
|---|---|---|
| GitOps (ArgoCD / Flux) | Application manifests | Runtime state, PVC data |
| etcd backup | Control plane state | Application PVC data |
| Manual PVC snapshots | Volume data only | Kubernetes object relationships |
| **Velero** | Both K8s objects and PVC data | Nothing — this is the complete solution |

---

## Recommended platform setup

When you add Velero to your platform, set it up with these practices from the start:

- **Scheduled backups** — at minimum nightly, plus a pre-maintenance backup before any risky operation.
- **Retention policy** — keep 30 days of daily backups, 90 days of weekly backups for compliance.
- **Object storage with versioning** — enable versioning and MFA-delete protection on your backup bucket so backups cannot be accidentally overwritten or deleted.
- **Regular restore tests** — schedule a monthly restore into a throwaway namespace to verify your backups actually work. A backup you have never tested is not a backup.
- **Alerts on backup failure** — hook Velero's metrics into Prometheus and alert if a scheduled backup does not complete. Silent backup failures are the worst kind.
- **Separate backup credentials** — the IAM role or service account Velero uses to write to object storage should be separate from your application credentials and locked down to that bucket only.

---

## Further reading

- [Velero official documentation](https://velero.io/docs/)
- [Velero GitHub](https://github.com/vmware-tanzu/velero)
- [CSI snapshot support](https://velero.io/docs/main/csi/)
- [Backup storage locations](https://velero.io/docs/main/backup-storage-location/)
