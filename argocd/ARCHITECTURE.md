# ArgoCD GitOps Architecture

Production-grade ArgoCD setup with ApplicationSet pattern and shared Helm chart for microservices.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       One-Time Setup                         │
│  kubectl apply -f projects/platform-team.yaml (RBAC)         │
│  kubectl apply -f bootstrap/root-app.yaml     (Watcher)      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  root-app syncs argocd/applicationsets/ from Git            │
│  └─ Creates: ApplicationSet (platform-apps)                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  ApplicationSet scans apps/**/config.json                    │
│  └─ Generates: Application per config.json found            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Applications deploy microservices (ordered by syncWave)     │
│  └─ Helm charts rendered and applied to cluster             │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
apps/
  _charts/
    microservice/              # Shared Helm chart (ONE template)
      Chart.yaml               # Chart metadata
      values.yaml              # Default values template
      templates/
        namespace.yaml         # Creates namespace
        deployment.yaml        # Spring Boot app with health checks
        service.yaml           # ClusterIP service
        configmap.yaml         # Application configuration
  
  order-service/               # Microservice 1
    config.json                # {"namespace":"orders","syncWave":"3","chartPath":"apps/_charts/microservice"}
    values.yaml                # Production values
    values-dev.yaml            # Development overrides
  
  checkout-service/            # Microservice 2
    config.json                # {"namespace":"checkout","syncWave":"3","chartPath":"apps/_charts/microservice"}
    values.yaml                # Production values
    values-dev.yaml            # Development overrides

argocd/
  bootstrap/
    root-app.yaml              # ONLY manually-applied file (watches applicationsets/)
  
  projects/
    platform-team.yaml         # AppProject (RBAC boundaries)
  
  applicationsets/
    platform-apps.yaml         # ApplicationSet (app discovery via config.json)
```

---

## The Three Core Components

### 1. AppProject (`projects/platform-team.yaml`)

**Purpose:** Security boundary — defines WHAT apps can deploy WHERE.

**Key settings:**
```yaml
sourceRepos:
  - "https://github.com/medhunk94/platform-core.git"  # Only this repo

destinations:
  - namespace: orders      # Can deploy to orders namespace
  - namespace: checkout    # Can deploy to checkout namespace

namespaceResourceWhitelist:
  - group: "apps"
    kind: Deployment       # Can create Deployments
  - group: ""
    kind: ConfigMap        # Can create ConfigMaps
  - group: ""
    kind: Service          # Can create Services
```

**When validated:** Every time ArgoCD syncs an Application.

---

### 2. Root Application (`bootstrap/root-app.yaml`)

**Purpose:** The watcher — monitors Git for ApplicationSets.

**What it does:**
- Watches `argocd/applicationsets/` folder in Git
- Auto-creates ApplicationSets when new YAML appears
- Only file you manually apply: `kubectl apply -f bootstrap/root-app.yaml`

**Key config:**
```yaml
spec:
  project: platform-team
  source:
    repoURL: https://github.com/medhunk94/platform-core.git
    targetRevision: feature/systemcharts
    path: argocd/applicationsets  # ← Watches this path
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

### 3. ApplicationSet (`applicationsets/platform-apps.yaml`)

**Purpose:** App discovery robot — scans Git for microservices and generates Applications.

**How it works:**
1. **Generator** scans for `apps/**/config.json` files in Git
2. **Template** creates one Application per config.json found
3. **Conditional logic** handles shared chart vs dedicated chart:

```yaml
generators:
  - git:
      files:
        - path: "apps/**/config.json"

template:
  spec:
    source:
      path: '{{ if .chartPath }}{{ .chartPath }}{{ else }}{{ trimSuffix "/config.json" .path.path }}{{ end }}'
      
      helm:
        valueFiles:
          - '{{ if .chartPath }}../../{{ trimSuffix "/config.json" .path.path }}/values.yaml{{ else }}values.yaml{{ end }}'
          - '{{ if .chartPath }}../../{{ trimSuffix "/config.json" .path.path }}/values-dev.yaml{{ else }}values-dev.yaml{{ end }}'
```

**Example:**
```
Found: apps/order-service/config.json with chartPath="apps/_charts/microservice"
  ↓
Generated Application:
  - name: order-service
  - source.path: apps/_charts/microservice        ← Shared chart
  - helm.valueFiles: 
      - ../../apps/order-service/values.yaml      ← Order service's values
      - ../../apps/order-service/values-dev.yaml
  - destination.namespace: orders                 ← From config.json
```

---

## Shared Helm Chart Pattern

### Why Shared Chart?

All microservices have the same structure:
- Deployment (Spring Boot app)
- Service (ClusterIP)
- ConfigMap (environment variables)
- Same health checks, security context, resource limits

**Without shared chart:**
```
50 microservices × Chart.yaml + templates/ = 50 duplicate chart folders to maintain
```

**With shared chart:**
```
1 chart at apps/_charts/microservice/ + 50 value files = easy to maintain
```

### Shared Chart Templates

**`templates/deployment.yaml`** — parameterized deployment:
```yaml
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: {{ .Values.name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          envFrom:
            - configMapRef:
                name: {{ .Values.name }}-config
          livenessProbe:
            httpGet:
              path: {{ .Values.healthCheck.livenessPath }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          securityContext:
            runAsNonRoot: {{ .Values.securityContext.runAsNonRoot }}
            readOnlyRootFilesystem: {{ .Values.securityContext.readOnlyRootFilesystem }}
```

### Per-Microservice Values

Each microservice defines its own values:

**`apps/order-service/values.yaml`:**
```yaml
name: order-service
namespace: orders
image:
  repository: spring-boot-order-service
  tag: "1.0.0"
replicaCount: 3
config:
  SPRING_PROFILES_ACTIVE: "production"
  DATABASE_HOST: "postgres-orders.orders.svc.cluster.local"
```

**`apps/order-service/values-dev.yaml`** (overrides for dev):
```yaml
replicaCount: 1
resources:
  limits:
    memory: "512Mi"
config:
  SPRING_PROFILES_ACTIVE: "development"  
```

---

## How to Add a New Microservice

### Step 1: Create Values Files

```bash
mkdir apps/payment-service
```

**`apps/payment-service/config.json`:**
```json
{
  "namespace": "payment",
  "syncWave": "3",
  "chartPath": "apps/_charts/microservice"
}
```

**`apps/payment-service/values.yaml`:**
```yaml
name: payment-service
namespace: payment
image:
  repository: spring-boot-payment-service
  tag: "1.0.0"
replicaCount: 3
service:
  port: 8080
config:
  SPRING_PROFILES_ACTIVE: "production"
  DATABASE_HOST: "postgres-payment.payment.svc.cluster.local"
  PAYMENT_GATEWAY_URL: "https://api.stripe.com"
```

**`apps/payment-service/values-dev.yaml`:**
```yaml
replicaCount: 1
config:
  SPRING_PROFILES_ACTIVE: "development"
  PAYMENT_GATEWAY_URL: "https://sandbox.stripe.com"
```

### Step 2: Update AppProject

Add `payment` namespace to allowed destinations in `argocd/projects/platform-team.yaml`:

```yaml
destinations:
  - namespace: orders
    server: https://kubernetes.default.svc
  - namespace: checkout
    server: https://kubernetes.default.svc
  - namespace: payment       # ← Add this
    server: https://kubernetes.default.svc
```

### Step 3: Push to Git

```bash
git add apps/payment-service/ argocd/projects/platform-team.yaml
git commit -m "feat(apps): add payment-service microservice"
git push origin feature/systemcharts
```

### Step 4: Watch ArgoCD Sync (Automatic)

```bash
# Wait ~3 minutes or force refresh
kubectl get applications -n argocd

# Expected output:
NAME              SYNC      HEALTH
order-service     Synced    Healthy
checkout-service  Synced    Healthy
payment-service   Synced    Healthy  ← New!
```

**That's it!** No ApplicationSet changes, no Application YAML to write — discovered automatically.

---

## GitOps Workflow

### Change Flow: Update Replicas

**Developer task:** Scale order-service from 1 to 2 replicas in dev.

```bash
# 1. Edit values file
vim apps/order-service/values-dev.yaml
# Change: replicaCount: 1 → replicaCount: 2

# 2. Commit and push
git add apps/order-service/values-dev.yaml
git commit -m "scale: increase order-service replicas to 2 in dev"
git push origin feature/systemcharts

# 3. ArgoCD detects change (within 3 minutes)
# - Fetches new commit
# - Re-renders Helm chart
# - Detects Deployment.spec.replicas changed: 1 → 2
# - Applies patch to cluster
# - No kubectl commands needed!

# 4. Verify
kubectl get deployment order-service -n orders
# NAME            READY   UP-TO-DATE   AVAILABLE
# order-service   2/2     2            2
```

### Sync Process

```
Developer → Push to Git
    ↓
ArgoCD polls Git (every 3 min)
    ↓
Detects commit changes apps/order-service/values-dev.yaml
    ↓
Application "order-service" status: OutOfSync
    ↓
Automated sync triggered (syncPolicy.automated)
    ↓
Helm chart rendered with new values
    ↓
Diff: replicaCount 1 → 2
    ↓
kubectl apply -f (Server-Side Apply)
    ↓
Deployment scaled to 2 replicas
    ↓
Application status: Synced ✅
```

---

## Verification Commands

```bash
# 1. Check AppProject exists
kubectl get appproject platform-team -n argocd

# 2. Check root-app is synced
kubectl get application root-app -n argocd

# 3. Check ApplicationSet exists
kubectl get applicationset platform-apps -n argocd

# 4. Check generated Applications
kubectl get applications -n argocd
# Expected: order-service, checkout-service

# 5. Check actual deployments
kubectl get deployments -n orders
kubectl get deployments -n checkout

# 6. Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Open: http://localhost:8080
# Login: admin / <get password below>
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## Key Benefits

### 1. **Scale to 100+ Microservices**
- One shared chart vs 100 duplicate chart folders
- Add new service = 3 files (config.json, values.yaml, values-dev.yaml)
- No ApplicationSet modifications needed

### 2. **GitOps Native**
- Git is single source of truth
- Every change goes through pull requests
- Full audit trail via Git history
- Rollback = `git revert` + push

### 3. **Environment Promotion**
```yaml
# Production values
valueFiles:
  - values.yaml           # Base config
  - values-prod.yaml      # Production overrides

# Staging values
valueFiles:
  - values.yaml           # Base config
  - values-staging.yaml   # Staging overrides

# Dev values
valueFiles:
  - values.yaml           # Base config
  - values-dev.yaml       # Dev overrides
```

### 4. **Security by Default**
- AppProject enforces namespace boundaries
- Kyverno policies require: runAsNonRoot, resource limits, readOnlyRootFilesystem
- Shared chart templates bake in security best practices
- Developers can't bypass security — enforced at platform level

---

## Troubleshooting

### Application Not Appearing

```bash
# Check if config.json was discovered
kubectl get applicationset platform-apps -n argocd -o yaml | grep -A5 "apps/your-service"

# Force ApplicationSet refresh
kubectl annotate applicationset platform-apps -n argocd \
  argocd.argoproj.io/refresh=normal

# Check Application status
kubectl get application your-service -n argocd -o yaml | grep -A10 "status:"
```

### Application OutOfSync

```bash
# Check sync status
kubectl get application your-service -n argocd

# Manual sync (if automated disabled)
kubectl patch application your-service -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# Check errors
kubectl logs -n argocd deployment/argocd-application-controller | grep your-service
```

### AppProject Permission Denied

```bash
# Check if namespace in destinations list
kubectl get appproject platform-team -n argocd -o yaml | grep -A20 destinations

# Check if resource type in whitelist
kubectl get appproject platform-team -n argocd -o yaml | grep -A30 namespaceResourceWhitelist
```

---

## Summary

**Three files control everything:**
1. **`projects/platform-team.yaml`** — RBAC
2. **`bootstrap/root-app.yaml`** — monitors applicationsets/
3. **`applicationsets/platform-apps.yaml`** — discovers config.json files

**To add a microservice:**
1. Create `apps/my-service/config.json`, `values.yaml`, `values-dev.yaml`
2. Add namespace to AppProject
3. Push to Git
4. ArgoCD discovers and deploys automatically

**GitOps in action:**
- Change value file → Commit → Push → ArgoCD syncs within 3 minutes
- No kubectl needed after initial bootstrap
- Git history = deployment audit trail
