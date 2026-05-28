# Kubernetes Platform Engineering Portfolio

Production-grade platform engineering practices covering GitOps, autoscaling, policy enforcement, secrets management, and cloud infrastructure. Built with real microservices and tested both locally (kind) and cloud-ready (Azure AKS via Terraform).

---

## Projects

| Project | Purpose | Status |
|---|---|---|
| **[Python Microservices](apps/)** | FastAPI checkout service (HTTP → Kafka) + Kafka consumer order service. Real working apps with CI/CD, not demos. | ✅ Production images in GHCR |
| **[ArgoCD GitOps](argocd/)** | Multi-team GitOps with ApplicationSets. Checkout and orders teams deploy independently with RBAC isolation. | ✅ Deployed |
| **[KEDA Autoscaling](keda-event-driven-autoscaling/)** | Event-driven autoscaling based on Kafka lag. Scale from 0 to N based on workload, not CPU. | ✅ Configured |
| **[Kyverno Policies](kyverno-policy-engine/)** | Block privileged containers, require resource limits, enforce security standards at admission time. | ✅ 7 policies active |
| **[External Secrets](external-secrets/)** | Pull database passwords and API keys from Vault. Zero secrets in Git. | ✅ ESO + Vault deployed |
| **[Supply Chain Security](supply-chain-security/)** | Generate SBOMs, scan images with Trivy, track CVEs in Dependency-Track. | ✅ SBOM generation |
| **[Velero Backup](velero/)** | Scheduled namespace backups with MinIO backend. Tested restore paths. | ✅ Configured |
| **[Terraform Infrastructure](terraform/)** | Modular blueprints for Azure AKS + PostgreSQL + VNet. Secrets from Key Vault, not tfvars. | ✅ Blueprints designed |

---

## What Makes This Different

**Real Microservices**: Not placeholder YAML. The checkout-service is a FastAPI app that publishes to Kafka. The order-service consumes from Kafka with graceful shutdown. Both have Dockerfiles, CI/CD pipelines, and container images published to GitHub Container Registry.

**CI/CD Integration**: GitHub Actions workflow builds images, runs Trivy security scans, pushes to GHCR with branch tags. CodeQL v3 for code analysis.

**Multi-Team Structure**: Two separate teams (checkout-team, orders-team) with isolated namespaces, separate AppProjects in ArgoCD, and RBAC boundaries. Shows how platform scales across teams without stepping on each other.

**Zero Secrets in Git**: Database passwords pulled from HashiCorp Vault via External Secrets Operator. Terraform reads secrets from Azure Key Vault at runtime. No credentials in code or tfvars.

**Cloud-Ready Infrastructure**: Terraform uses modular blueprints pattern. Same modules work for dev/staging/prod. Azure AKS with auto-scaling (2-5 nodes), VNet-integrated PostgreSQL, Azure CNI networking, Calico network policy.

**Security by Default**: Kyverno blocks containers running as root, without resource limits, or using `:latest` tags. Images scanned before deployment. Network policies isolate pods.

---

## Tech Stack

| Component | Technology |
|---|---|
| **Applications** | Python 3.12, FastAPI, kafka-python 2.0.2 |
| **Local Cluster** | kind (Kubernetes in Docker) |
| **Cloud Infrastructure** | Terraform, Azure AKS, Azure PostgreSQL, Azure Key Vault |
| **GitOps** | ArgoCD 2.x, ApplicationSets, Helm 3 |
| **CI/CD** | GitHub Actions, Trivy scanner, CodeQL v3 |
| **Container Registry** | GitHub Container Registry (GHCR) |
| **Autoscaling** | KEDA 2.15.1, Kafka ScaledObject |
| **Policy Engine** | Kyverno v1.18.1 |
| **Secrets Management** | External Secrets Operator, HashiCorp Vault |
| **Message Broker** | Apache Kafka 3.9.0 (KRaft) |
| **Security Scanning** | Trivy 0.70.0, CycloneDX SBOM |
| **Backup** | Velero, MinIO |

---

## Microservices

### checkout-service (FastAPI)
- **Purpose**: HTTP API that accepts checkout requests and publishes to Kafka
- **Endpoints**: `POST /api/checkout`, `GET /health`, `GET /ready`
- **Tech**: FastAPI, uvicorn, kafka-python
- **Image**: `ghcr.io/medhunk94/checkout-service:feature-systemcharts`

### order-service (Kafka Consumer)
- **Purpose**: Consumes orders from Kafka topic, processes them with graceful shutdown
- **Tech**: Python, kafka-python, consumer group with offset management
- **Features**: Signal handlers (SIGTERM/SIGINT), structured logging
- **Image**: `ghcr.io/medhunk94/order-service:feature-systemcharts`

Both services have:
- Single-stage Dockerfiles (non-root user 1001)
- GitHub Actions CI/CD pipeline
- Trivy security scanning
- Helm values for dev and production
- Health/readiness probes for Kubernetes

---

## Infrastructure as Code

The `terraform/` directory contains production-grade Azure infrastructure using a modular blueprints pattern:

**Blueprints** (reusable modules):
- `resource-group/`: Azure resource group
- `vnet/`: Virtual network with address space
- `subnet/`: Subnet with service endpoints
- `nsg/`: Network security groups
- `aks/`: AKS cluster with auto-scaling, Azure CNI, Calico network policy
- `postgresql/`: PostgreSQL with VNet integration, SSL enforcement

**Environment Composition**:
- `environments/dev/`: Composes blueprints into complete infrastructure
- Remote state in Azure Storage
- Secrets retrieved from Azure Key Vault at runtime (never in code)

**Key Features**:
- Auto-scaling AKS (2-5 nodes based on workload)
- VNet-integrated PostgreSQL (no public access)
- SystemAssigned managed identity (no credential management)
- All resources tagged for cost tracking

See [terraform/README.md](terraform/README.md) for architecture details and Terraform concepts implemented.

---

## How It Works Together

**Build Time**:
1. Developer commits code to GitHub
2. GitHub Actions builds Docker image
3. Trivy scans for vulnerabilities
4. Image pushed to GHCR with branch tag
5. CycloneDX generates SBOM

**Deploy Time**:
1. Developer updates Helm values in Git
2. ArgoCD detects change via ApplicationSet
3. Kyverno validates pod security before admission
4. ESO pulls secrets from Vault, creates K8s Secret
5. Pod starts with secrets mounted

**Runtime**:
1. checkout-service receives HTTP POST, publishes to Kafka
2. order-service consumes message from Kafka topic
3. KEDA monitors consumer group lag
4. When lag > threshold, KEDA scales order-service pods
5. Velero takes scheduled backups of all namespaces

**Failure Recovery**:
1. Namespace accidentally deleted
2. `velero restore create --from-backup latest`
3. All resources restored from MinIO backup

---

## Running Locally

### Prerequisites
- Docker Desktop
- kind
- kubectl
- Helm 3

### Quick Start

```bash
# Create cluster
kind create cluster --name k8s-platform-dev

# Deploy projects (see individual README files)
cd external-secrets && ./setup.sh
cd ../argocd && kubectl apply -k install/
cd ../kyverno-policy-engine && helm install kyverno ...
```

Each project folder has detailed setup instructions.

---

## Current Status

### ✅ Python Microservices
- **checkout-service**: FastAPI app publishing to Kafka
- **order-service**: Kafka consumer with graceful shutdown
- **CI/CD**: GitHub Actions building and pushing to GHCR
- **Images**: Public in GitHub Container Registry
- **Repository**: https://github.com/medhunk94/platform-core.git (branch: feature/systemcharts)

### ✅ ArgoCD Multi-Team GitOps
- **Deployed**: http://localhost:8081
- **Teams**: checkout-team, orders-team with RBAC isolation
- **ApplicationSets**: Auto-discover services per team
- **Projects**: Separate AppProjects enforce boundaries

### ✅ External Secrets Operator
- **ESO**: Deployed and syncing secrets from Vault
- **Vault**: Running in dev mode with sample secrets
- **Integration**: Services pull DB passwords from Vault

### ✅ Kyverno Policy Engine
- **Policies**: 7 ClusterPolicies active
- **Enforcement**: Block privileged containers, require resource limits, reject `:latest` tags

### ✅ Terraform Infrastructure
- **Blueprints**: 6 reusable modules (AKS, PostgreSQL, VNet, subnet, NSG, resource-group)
- **Security**: Secrets from Azure Key Vault, not tfvars
- **Status**: Designed for Azure AKS, requires subscription + Key Vault prerequisites

---

## Repository Structure

```
platform-core/
├── apps/                          # Microservices
│   ├── checkout-team/
│   │   └── checkout-service/      # FastAPI producer
│   └── orders-team/
│       └── order-service/         # Kafka consumer
├── argocd/                        # GitOps configuration
│   ├── applicationsets/           # Team app discovery
│   ├── projects/                  # RBAC boundaries
│   └── bootstrap/                 # Root app
├── external-secrets/              # ESO + Vault setup
├── keda-event-driven-autoscaling/ # KEDA configuration
├── kyverno-policy-engine/         # Policy definitions
├── supply-chain-security/         # SBOM generation
├── terraform/                     # Cloud infrastructure
│   ├── blueprints/                # Reusable modules
│   └── environments/dev/          # Dev composition
└── velero/                        # Backup configuration
```
