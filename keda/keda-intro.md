# KEDA — Kubernetes Event-Driven Autoscaling

## What is KEDA?

KEDA is an open-source component you install into your Kubernetes cluster. It extends the built-in HPA to scale your workloads based on **external event sources** — message queues, databases, cron schedules, HTTP traffic, and dozens more — instead of just CPU and memory.

**Real-world analogy:** Imagine a warehouse packing team. The team manager doesn't count how tired the workers are (CPU) to decide whether to call in more staff. Instead, they look at the conveyor belt backlog — how many unboxed parcels are piling up. When parcels stack up, they call in more workers. When the belt is clear, staff go home. KEDA does exactly this for your Kubernetes pods, watching the event backlog instead of CPU.

---

## What problem does it solve?

### The core problem: CPU is the wrong metric for event-driven workloads

Kubernetes' built-in HPA scales on CPU and memory. That works well for request-response services (REST APIs, frontends). It fails for **event-driven workloads** like:

- **Kafka consumers** — A pod consuming messages from a Kafka topic might be at 5% CPU while 50,000 unread messages pile up. HPA sees no pressure and does nothing.
- **Queue workers** — A background job processor polling RabbitMQ has nothing to do when the queue is empty. You are paying for idle pods that should be scaled to zero.
- **Scheduled batch jobs** — You want exactly 10 pods running at 2am for a nightly report and zero at any other time. HPA has no concept of a schedule.

Without KEDA, the outcomes are:

| Scenario | Without KEDA | With KEDA |
|---|---|---|
| Kafka consumer falls behind | Lag grows indefinitely, messages delayed for hours | Detects lag > threshold, scales up consumers automatically |
| Queue empty overnight | Idle consumer pods running at cost all night | Scales down to 0 when queue is empty, saves 100% overnight cost |
| Nightly batch job | Manually edit replicas in a cron job script | CronTrigger: 10 pods at 2am, 0 pods at 3am — fully declarative |
| Black Friday traffic spike | Pre-provision peak capacity all week "just in case" | Scale from 0 to 50 workers in seconds as orders queue up |

---

## Why do we need it?

### 1. Scale on what actually matters

CPU reflects *how busy the CPU is*, not *how much work is waiting*. For a Kafka consumer, the right question is: **how many messages are unread?** KEDA lets you answer that question natively.

### 2. Scale to zero

The built-in HPA cannot scale a deployment below 1 replica. KEDA can scale to **zero** — no pods running when there is nothing to do. This is the single biggest cost saving for async workloads.

```
A Kafka consumer that processes 1 million messages during business hours
and sits idle for 16 hours every night:

Without KEDA:  3 idle pods × 16 hours × $0.05/pod/hour = $2.40/night = ~$876/year wasted
With KEDA:     0 pods during idle → $0
```

### 3. 60+ built-in scalers, no custom code

KEDA ships with scalers for: Kafka, RabbitMQ, AWS SQS, Azure Service Bus, GCP Pub/Sub, Redis, PostgreSQL, MySQL, Prometheus metrics, HTTP requests, Cron schedules, and 50+ more.

Without KEDA you would need to write a custom Prometheus exporter + HPA custom metrics adapter for every external system. With KEDA, you declare it in YAML.

### 4. Works alongside HPA — doesn't replace it

KEDA does not compete with HPA. It creates and manages an HPA object behind the scenes. Your existing HPA knowledge and `behavior` tuning (`scaleDown.stabilizationWindowSeconds`, etc.) still applies and is passed through via the `advanced` block.

---

## How KEDA works (step by step)

```
KEDA installs two components into the cluster:
  - keda-operator        : watches ScaledObject CRDs, creates/updates HPA objects
  - keda-metrics-apiserver: exposes external metrics to the HPA via the metrics API

Every pollingInterval seconds:

1. keda-operator queries the external source (e.g., Kafka consumer group lag)
2. Converts the raw value into a metric the HPA understands
3. HPA runs its normal calculation:
     desired replicas = ceil(current replicas × (current lag / lagThreshold))
4. If the metric is zero (empty queue), KEDA scales the deployment to 0
5. When a new message arrives, KEDA detects it and scales back to minReplicaCount first,
   then HPA takes over from there
```

### Activation threshold

KEDA has a concept of **activation**: the deployment stays at 0 replicas until the metric crosses `activationLagThreshold`. This prevents a single stray message from immediately spinning up pods.

```
activationLagThreshold: 10  →  stay at 0 pods unless lag > 10 messages
lagThreshold: 100           →  once active, add 1 pod per 100 messages of lag
```

---

## Key configuration fields in this ScaledObject

```yaml
spec:
  scaleTargetRef:
    name: kafka-consumer          # The Deployment to scale

  pollingInterval: 15             # Check Kafka lag every 15 seconds
  cooldownPeriod: 300             # Wait 5 minutes after last event before scaling down
  minReplicaCount: 1              # Keep at least 1 pod running (avoids cold start delay)
  maxReplicaCount: 20             # Hard ceiling — protect cluster capacity

  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300   # Prevent aggressive scale-down flapping
          policies:
            - type: Pods
              value: 2
              periodSeconds: 120            # Remove at most 2 pods every 2 minutes

  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka-broker.kafka.svc.cluster.local:9092
        consumerGroup: my-service-consumer-group
        topic: platform-events
        lagThreshold: "100"               # Scale when lag > 100 msgs per partition
        activationLagThreshold: "10"      # Stay at 0 unless lag > 10 (noise filter)
```

---

## When to use KEDA vs plain HPA

| Signal you need KEDA | Stick with plain HPA |
|---|---|
| Scaling a Kafka / RabbitMQ / SQS consumer | Scaling a REST API or web frontend |
| You want pods to go to zero when idle | Minimum 1 replica is acceptable |
| Scaling driven by an external system (queue depth, DB row count) | Scaling driven by CPU or memory |
| Scheduled scale-up/down (cron) | Continuous traffic with no schedule |
| You have many different trigger types per service | Single CPU/memory threshold is enough |

---

## Common mistakes

- **`minReplicaCount: 0` with a Kafka consumer** — When a message arrives and all pods are at 0, there is a cold start delay of 5–15 seconds before a pod is ready. If your downstream SLA cannot tolerate this, keep `minReplicaCount: 1`.
- **`lagThreshold` too low** — Setting it to `"1"` means KEDA scales up for every single message. You get constant scale-up/down thrashing. Set it based on how many messages one pod can process in `cooldownPeriod` seconds.
- **Forgetting `cooldownPeriod`** — Without a cooldown, KEDA scales down immediately after messages drain. If the producer sends messages in bursts, you will see repeated scale-up/scale-down cycles within minutes.
- **GitOps conflict with ArgoCD** — Same problem as plain HPA. ArgoCD will reset `spec.replicas` on every sync. Add this to your ArgoCD Application:

  ```yaml
  spec:
    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas
  ```

- **KEDA not installed** — Applying a `ScaledObject` without KEDA installed does nothing (the CRD does not exist). Verify: `kubectl get crd scaledobjects.keda.sh`

