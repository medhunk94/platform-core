# KEDA Architecture — Full Overview

## System context

KEDA sits between your external event sources (Kafka, queues, schedules, metrics)  
and the Kubernetes control plane. It does not replace any Kubernetes primitives —  
it augments them by feeding external signal into the existing HPA machinery.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  EXTERNAL WORLD                                                              │
│                                                                              │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │ Apache Kafka │  │ RabbitMQ / SQS  │  │  Prometheus  │  │ Cron/Timer  │  │
│  │ (topic lag)  │  │ (queue depth)   │  │  (metric)    │  │ (schedule)  │  │
│  └──────┬───────┘  └────────┬────────┘  └──────┬───────┘  └──────┬──────┘  │
└─────────┼──────────────────┼──────────────────┼─────────────────┼──────────┘
          │                  │                  │                 │
          ▼                  ▼                  ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  KEDA (keda namespace)                                                       │
│                                                                              │
│  ┌────────────────────────┐       ┌──────────────────────────────────────┐  │
│  │   keda-operator        │       │   keda-metrics-apiserver             │  │
│  │                        │       │                                      │  │
│  │  • Watches ScaledObject│       │  • Implements external.metrics.k8s  │  │
│  │    CRDs                │       │    .io API group                    │  │
│  │  • Polls scalers every │       │  • Translates raw scaler values     │  │
│  │    pollingInterval sec │       │    into HPA-consumable metrics      │  │
│  │  • Creates / updates   │       │  • HPA queries this server          │  │
│  │    HPA objects         │       │    every 15s (default)              │  │
│  │  • Manages 0-replica   │       │                                      │  │
│  │    activation logic    │       └──────────────────────────────────────┘  │
│  └────────────────────────┘                                                  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │   keda-admission-webhooks                                             │   │
│  │   • Validates ScaledObject / ScaledJob manifests at admission time   │   │
│  │   • Rejects invalid configs before they reach the operator           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
          │
          │  creates / manages
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  KUBERNETES CONTROL PLANE                                                    │
│                                                                              │
│  ┌──────────────────────┐      ┌───────────────────────────────────────┐   │
│  │  HorizontalPodAuto-  │      │  Target Deployment (app namespace)    │   │
│  │  scaler (managed by  │─────►│                                       │   │
│  │  KEDA operator)      │      │  kafka-consumer   replicas: 0 → N     │   │
│  └──────────────────────┘      └───────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data flow: Kafka lag-based scaling (step by step)

```
t=0s   ScaledObject created in cluster
       keda-operator reads it, connects to Kafka broker
       keda-operator creates HPA object pointing to keda-metrics-apiserver

t=15s  keda-operator polls Kafka:
         consumer group "my-service-consumer-group", topic "platform-events"
         Partition 0 lag: 0, Partition 1 lag: 0, Partition 2 lag: 0
         Total lag: 0  →  activationLagThreshold not met
         Deployment scaled to 0 replicas

t=45s  Messages start arriving on "platform-events" topic
         Total lag: 35  →  still below activationLagThreshold (10) ... wait
         Actually lag=35 > activationLagThreshold=10
         keda-operator activates: scales Deployment to minReplicaCount=1

t=60s  Lag continues growing: 350 messages
         desired replicas = ceil(1 × 350/100) = 4
         HPA issues scale-up to 4 replicas

t=90s  Kafka consumer group has 4 pods consuming
         Lag dropping: 180 messages
         desired replicas = ceil(4 × 180/100) = 2  → within stabilization window, no scale-down yet

t=600s Lag reaches 0.  cooldownPeriod=300s starts.
t=900s cooldownPeriod elapsed, all lag gone → scale to minReplicaCount=1
```

---

## Scaling formula

KEDA exposes the lag as an external metric. The HPA uses:

$$
\text{desired replicas} = \left\lceil \text{current replicas} \times \frac{\text{current metric value}}{\text{threshold}} \right\rceil
$$

For Kafka with `lagThreshold: 100` and current lag of 430 across a deployment with 3 pods:

$$
\text{desired} = \left\lceil 3 \times \frac{430}{100} \right\rceil = \left\lceil 12.9 \right\rceil = 13
$$

---

## Activation vs scaling

KEDA has two distinct phases:

| Phase | Condition | Action |
|---|---|---|
| **Inactive** | `metric < activationThreshold` | Keep Deployment at 0 replicas |
| **Active** | `metric ≥ activationThreshold` | Scale to `minReplicaCount`, then HPA takes over |

This two-phase model prevents noisy triggers (a single message, one data point) from  
waking up pods unnecessarily.

---

## Network topology and security boundaries

```
┌──────────────────────────────────────────────────────────────────┐
│  keda namespace                                                   │
│                                                                   │
│  keda-operator          keda-metrics-apiserver                   │
│  (ClusterRole:          (aggregated API server,                  │
│   read ScaledObjects,    port 6443, TLS)                         │
│   manage HPAs)                                                    │
└──────────────────────────────┬───────────────────────────────────┘
                               │ NetworkPolicy (egress only to
                               │ Kafka brokers, Prometheus, etc.)
                               ▼
                    External sources (per-trigger)
```

**Key security points:**
- KEDA operator uses a `ClusterRole` to read ScaledObjects across all namespaces  
  and manage HPA objects — this is by design and cannot be namespace-scoped.
- Scaler credentials (Kafka SASL password, RabbitMQ URI) **must** live in  
  `kind: Secret` objects, referenced by `authenticationRef` — never in plain YAML.
- `TriggerAuthentication` or `ClusterTriggerAuthentication` objects decouple  
  credentials from ScaledObject definitions.

---

## High availability design

```
keda namespace (production)

keda-operator:              2 replicas (leader-election enabled)
keda-metrics-apiserver:     2 replicas (stateless, any replica serves)
keda-admission-webhooks:    2 replicas

Node anti-affinity:         spread across 3 AZs using topologyKey: topology.kubernetes.io/zone
PodDisruptionBudget:        minAvailable: 1 for each component
```

See [ha-and-reliability.md](../production-considerations/ha-and-reliability.md) for full manifests.

---

## Version compatibility matrix

| KEDA | Kubernetes | Helm chart |
|---|---|---|
| 2.15.x | 1.27 – 1.31 | kedacore/keda 2.15.x |
| 2.14.x | 1.26 – 1.30 | kedacore/keda 2.14.x |
| 2.13.x | 1.25 – 1.29 | kedacore/keda 2.13.x |

Always match KEDA version to your Kubernetes minor version range.  
Check [https://keda.sh/docs/latest/operate/cluster/](https://keda.sh/docs/latest/operate/cluster/) for the current matrix.
