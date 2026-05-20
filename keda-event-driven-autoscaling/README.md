# KEDA — Event-Driven Autoscaling Platform

> **Mini Platform Engineering Portfolio Project**  

---

## What this project delivers

| Capability | What's included |
|---|---|
| **Architecture** | Component diagrams, data-flow, HA design |
| **Scaling Scenarios** | Kafka, RabbitMQ, Cron, Prometheus, HTTP |
| **Manifests** | Namespace, RBAC, ScaledObjects, ScaledJobs |
| **Helm** | Production values, environment overlays |
| **Monitoring** | ServiceMonitor, Grafana dashboard, alert rules |
| **Load Testing** | k6 scripts to validate autoscaling behaviour |
| **Troubleshooting** | Runbook, common failure modes |
| **Production Hardening** | Security, HA, cost optimisation |

---

## Architecture at a glance

```
┌────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                          │
│                                                                    │
│  ┌─────────────────┐        ┌────────────────────────────────────┐ │
│  │  External Source │        │           KEDA                     │ │
│  │  ─────────────  │        │  ┌──────────────┐  ┌────────────┐  │ │
│  │  Kafka Topic     │◄──────►│  │ keda-operator│  │metrics-api │  │ │
│  │  RabbitMQ Queue  │        │  └──────┬───────┘  └─────┬──────┘  │ │
│  │  SQS / PubSub    │        │         │                 │         │ │
│  │  Prometheus      │        │    Creates/updates   Exposes ext.  │ │
│  │  Cron Schedule   │        │    HPA objects       metrics API   │ │
│  └─────────────────┘        └─────────┼───────────────┼──────────┘ │
│                                        ▼               ▼            │
│                              ┌──────────────────────────────────┐  │
│                              │       Kubernetes HPA             │  │
│                              │  (managed by KEDA, not you)      │  │
│                              └────────────┬─────────────────────┘  │
│                                           ▼                         │
│                              ┌──────────────────────────────────┐  │
│                              │   Target Workload (Deployment)   │  │
│                              │   kafka-consumer  0 → N pods     │  │
│                              └──────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

---

## Project structure

```
keda-event-driven-autoscaling/
├── README.md                        ← you are here
├── architecture/
│   ├── overview.md                  ← full architecture narrative
│   └── keda-components.md           ← operator, metrics-server, webhooks deep dive
├── scenarios/
│   ├── kafka-consumer-scaling.md    ← Kafka lag-based scaling (most common)
│   ├── rabbitmq-queue-scaling.md    ← RabbitMQ with AMQP trigger
│   ├── cron-based-scaling.md        ← scheduled scaling, nightly batch jobs
│   └── prometheus-metrics-scaling.md← custom Prometheus metric as trigger
├── manifests/
│   ├── namespace.yaml               ← namespace + resource quotas
│   ├── rbac.yaml                    ← ServiceAccount, Role, RoleBinding
│   ├── kafka-scaledobject.yaml      ← production Kafka ScaledObject
│   ├── rabbitmq-scaledobject.yaml   ← RabbitMQ ScaledObject
│   ├── cron-scaledobject.yaml       ← Cron-based ScaledObject
│   ├── prometheus-scaledobject.yaml ← Prometheus trigger ScaledObject
│   └── batch-scaledjob.yaml         ← ScaledJob for ephemeral batch workloads
├── helm/
│   ├── values-base.yaml             ← shared base values
│   ├── values-prod.yaml             ← production overrides
│   └── install.sh                   ← idempotent install/upgrade script
├── monitoring/
│   ├── servicemonitor.yaml          ← Prometheus scrape config for KEDA
│   ├── alerts.yaml                  ← PrometheusRule — lag spike, scaler errors
│   └── grafana-dashboard.json       ← importable Grafana dashboard (KEDA overview)
├── load-testing/
│   ├── k6-kafka-load-test.js        ← k6 script: produce messages, watch scaling
│   └── run-load-test.sh             ← orchestration wrapper
├── troubleshooting/
│   ├── runbook.md                   ← step-by-step incident response
│   └── common-issues.md             ← known failure modes + fixes
└── production-considerations/
    ├── security.md                  ← RBAC, sealed secrets, network policies
    ├── ha-and-reliability.md        ← HA operator setup, PodDisruptionBudget
    └── cost-optimisation.md         ← scale-to-zero strategy, right-sizing
```

---

## Quick start

```bash
# 1. Install KEDA (production values)
cd helm/
bash install.sh

# 2. Apply the platform namespace and RBAC
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

# 3. Deploy a scenario (example: Kafka)
kubectl apply -f manifests/kafka-scaledobject.yaml

# 4. Verify
kubectl get scaledobject -n platform
kubectl get hpa -n platform

# 5. Trigger load and watch scaling
cd load-testing/
bash run-load-test.sh
kubectl get pods -n platform -w
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| `kubectl` | ≥ 1.28 | Cluster interaction |
| `helm` | ≥ 3.12 | KEDA installation |
| `k6` | ≥ 0.50 | Load testing |
| `kaf` or `kafka-cli` | any | Kafka inspection |
| Prometheus + Grafana | any | Monitoring stack |

---

## Design decisions

**Why Helm for KEDA install, but raw manifests for ScaledObjects?**  
KEDA itself has many tunables that benefit from Helm values (resource limits, replicas, TLS).  
ScaledObjects are workload-specific and belong in the application team's GitOps repo alongside  
their Deployment manifests — not inside a shared Helm chart.

**Why `minReplicaCount: 1` on most ScaledObjects?**  
Scale-to-zero introduces a cold start delay (typically 15–30 seconds). For latency-sensitive  
consumers, keeping one warm pod is the right trade-off. The Cron scenario uses `minReplicaCount: 0`  
because the workload is explicitly batch and cold-start cost is acceptable.

**Why `stabilizationWindowSeconds: 300` on scale-down?**  
Kafka partition rebalancing is expensive. Scaling down too aggressively causes repeated  
rebalance storms. Five minutes of stabilisation prevents that.
