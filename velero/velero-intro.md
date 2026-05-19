# Velero — Kubernetes Backup and Restore

## What is Velero?

Velero is an open-source tool that backs up your Kubernetes cluster — not just the configuration files, but also the actual data stored in persistent volumes. It pushes those backups to object storage like S3, Google Cloud Storage, or Azure Blob, and lets you restore them whenever you need to.

Think of it as a time machine for your cluster. If something goes wrong — someone deletes the wrong namespace, a cluster upgrade fails, or a whole region goes down — Velero lets you go back to a known good state.

---

## What problem does it solve?

People often assume that because Kubernetes is declarative and everything lives in YAML, recovery is just a matter of re-applying manifests from Git. That is true for stateless apps. But most real workloads are not stateless.

Consider these scenarios:

- A developer runs `kubectl delete namespace payments` by mistake. Gone in seconds. GitOps restores the deployment and the config, but the PostgreSQL PVC with six months of transaction data is not coming back from Git.
- You upgrade Kubernetes from 1.28 to 1.29. Something breaks at the cluster level and you need to roll back. There is no native rollback in Kubernetes.
- You need to move all workloads from one cloud provider to another. Re-deploying apps is the easy part. Moving stateful data across clouds without Velero is a manual, painful process.
- Your compliance team asks for proof that you can restore the cluster within 4 hours. Without a tested backup strategy, you have no answer.

This is the gap Velero fills. GitOps handles manifests. Velero handles state.

---

## Why platform teams should include it

If you are running a shared Kubernetes platform for multiple teams, backup is not optional — it is part of the reliability contract you own on behalf of every tenant.

Here is why it belongs in your platform from day one:

**You are responsible for what runs on your cluster.** When a team loses data because of a platform-level failure or an operator mistake, they come to you. Having Velero with scheduled backups means you have a recovery path instead of an apology.

**GitOps alone is not enough.** Tools like ArgoCD and Flux are excellent for deploying applications consistently, but they do not capture the runtime state of your databases or file stores. Velero and GitOps are complementary — you need both.

**Cluster migrations happen more than you expect.** Version upgrades, cloud provider changes, region moves, or consolidating clusters — all of these are significantly easier when you can backup one cluster and restore to another.

**Compliance and auditing require it.** Finance, healthcare, and other regulated industries have data retention and recovery time requirements. Velero gives you scheduled, verifiable, documented backups that satisfy those requirements.

**It enables safe cluster operations.** When your platform team needs to do risky work — node drains, upgrades, storage migrations — a pre-operation backup means you can always undo it.

---

## How it works

Velero runs as a controller inside your cluster. When a backup is triggered (manually or on a schedule), it:

1. Queries the Kubernetes API and serialises all objects — Deployments, Services, ConfigMaps, Secrets, RBAC, CRDs, everything — into JSON files.
2. Triggers volume snapshots for any Persistent Volume Claims, using either CSI snapshots or cloud provider snapshot APIs.
3. Uploads all of it to your configured object storage bucket.

On restore, it does the reverse — reads from object storage, recreates the Kubernetes objects via the API, and restores volume data from the snapshots.

```
Velero Controller
      │
      ├──► Serialises K8s objects (Deployments, PVCs, ConfigMaps, etc.)
      ├──► Snapshots Persistent Volumes via CSI or cloud APIs
      └──► Pushes everything to S3 / GCS / Azure Blob

Restore:
      Object Storage ──► Velero ──► Recreates objects + restores PV data
```