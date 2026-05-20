# KEDA Troubleshooting Runbook

## How to use this runbook

Start at **Step 1** and work down. Each step narrows the failure domain.  
Most issues are caught by steps 1–4. Only rare platform-level failures  
require steps 5–7.

---

## Step 1: Is KEDA itself healthy?

```bash
# Are all three KEDA pods running?
kubectl get pods -n keda

# Expected:
# keda-operator-xxxx                  1/1     Running
# keda-metrics-apiserver-xxxx         1/1     Running
# keda-admission-webhooks-xxxx        1/1     Running

# If any pod is NOT in Running state:
kubectl describe pod <pod-name> -n keda
kubectl logs <pod-name> -n keda --previous   # check crash logs

# Is the external metrics APIService registered and available?
kubectl get apiservice v1beta1.external.metrics.k8s.io
# STATUS must be "True". If it is False:
kubectl describe apiservice v1beta1.external.metrics.k8s.io
```

**If KEDA pods are crashlooping:** check Helm values for resource limits.  
A 256Mi memory limit on a cluster with 50+ ScaledObjects will OOM the operator.

---

## Step 2: Is the ScaledObject in a healthy state?

```bash
# List all ScaledObjects and their Ready condition
kubectl get scaledobject -n platform

# NAME                           SCALETARGETKIND      SCALETARGETNAME    READY   ACTIVE   ...
# order-processor-scaledobject   apps/v1.Deployment   order-processor    True    True     ...

# Detailed status with events
kubectl describe scaledobject order-processor-scaledobject -n platform
```

Look for these conditions:
| Condition | Meaning |
|---|---|
| `Ready: True` | ScaledObject is healthy, HPA is created |
| `Ready: False` | Problem detected — read the `Message` field |
| `Active: True` | Metric is above activationThreshold, HPA is active |
| `Active: False` | Metric is below activationThreshold (could be correct — empty queue) |
| `Paused: True` | ScaledObject is manually paused via annotation |

**Common `Ready: False` reasons:**

```
ScaleTarget Not Found
→ The Deployment referenced in scaleTargetRef does not exist.
   Fix: kubectl get deployment <name> -n platform  (apply the Deployment first)

Unable to get KEDA API Groups
→ KEDA CRDs not installed or API server not ready.
   Fix: helm upgrade keda kedacore/keda ...

Scaler not found for type: kafka
→ Typo in trigger type name.
   Fix: valid names are lowercase: kafka, rabbitmq, prometheus, cron, redis, etc.

Error connecting to Kafka broker
→ Network/auth issue. See Step 4.
```

---

## Step 3: Is the HPA being created and working?

```bash
# KEDA creates an HPA with the name from advanced.horizontalPodAutoscalerConfig.name
kubectl get hpa -n platform
kubectl describe hpa order-processor-hpa -n platform
```

Look for:
```
Conditions:
  ScalingActive   True    ValidMetricFound   ...
  AbleToScale     True    SucceededGetScale  ...
  ScalingLimited  False   DesiredWithinRange ...
```

**ScalingActive = False (FailedGetExternalMetric)**:
```bash
# HPA cannot reach the KEDA metrics API server
kubectl get --raw \
  "/apis/external.metrics.k8s.io/v1beta1/namespaces/platform/s0-kafka-platform-events" \
  | jq .

# If this returns an error, the metrics APIService is broken
# Check: kubectl get apiservice v1beta1.external.metrics.k8s.io
```

**ScalingLimited = True (TooManyReplicas)**:
```
→ Desired replicas exceeds maxReplicaCount. Consider increasing maxReplicaCount
  (but ensure it doesn't exceed Kafka partition count for Kafka scalers).
```

---

## Step 4: Is the scaler reaching the external source?

### Kafka

```bash
# Check if KEDA can connect to Kafka
kubectl logs -n keda -l app=keda-operator --since=5m \
  | grep -i "kafka\|error\|order-processor"

# Manually test Kafka connectivity from a pod in the cluster
kubectl run kafka-debug --rm -it \
  --image=confluentinc/cp-kafka:7.5.0 \
  --restart=Never -- \
  kafka-consumer-groups.sh \
    --bootstrap-server kafka-broker.kafka.svc.cluster.local:9092 \
    --describe --group order-processor-consumer-group

# If SASL error:
# → Check TriggerAuthentication secret keys match what KEDA expects
kubectl get secret kafka-credentials -n platform -o jsonpath='{.data}' | jq 'keys'
kubectl describe triggerauthentication kafka-trigger-auth -n platform
```

### RabbitMQ

```bash
# Test the Management API endpoint KEDA uses
kubectl run rmq-debug --rm -it \
  --image=curlimages/curl:latest \
  --restart=Never -- \
  curl -u keda-user:PASSWORD \
  http://rabbitmq.rabbitmq.svc.cluster.local:15672/api/queues/%2F/email-notifications \
  | python3 -m json.tool | grep messages_ready
```

### Prometheus

```bash
# Test the PromQL query that KEDA uses
kubectl run prom-debug --rm -it \
  --image=curlimages/curl:latest \
  --restart=Never -- \
  curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(payment_events_total{risk_level="high"}[2m]))' \
  | python3 -m json.tool
```

---

## Step 5: Scale-to-zero is not happening

```bash
# Is cooldownPeriod still running?
kubectl describe scaledobject <name> -n platform
# Look for: "Last Active Time" — cooldown runs from this timestamp

# Is something holding the replica count at 1?
# Check if there's a separate HPA or VPA on the same Deployment
kubectl get hpa,vpa -n platform

# Is minReplicaCount set to 1?
kubectl get scaledobject <name> -n platform -o jsonpath='{.spec.minReplicaCount}'

# Is the ScaledObject paused?
kubectl get scaledobject <name> -n platform \
  -o jsonpath='{.metadata.annotations.autoscaling\.keda\.sh/paused-replicas}'
```

---

## Step 6: Scaling is oscillating (pods scale up and down repeatedly)

This is a scale-thrashing problem — usually caused by:

| Cause | Diagnosis | Fix |
|---|---|---|
| `cooldownPeriod` too short | Replicas drop to 0 then immediately re-activate | Increase `cooldownPeriod` to 300s |
| `stabilizationWindowSeconds` too short | Replica count changes every poll | Set `scaleDown.stabilizationWindowSeconds: 300` |
| Kafka rebalancing triggers lag spike | Consumer group rebalances mid-scale, lag briefly spikes | Increase `cooldownPeriod`, reduce `scaleDown.policies[].value` |
| `activationLagThreshold` not set | Any single message wakes the Deployment | Add `activationLagThreshold: "10"` |

---

## Step 7: Collecting logs for escalation

```bash
# Full operator logs (last 30 minutes)
kubectl logs -n keda -l app=keda-operator --since=30m > /tmp/keda-operator.log

# Full metrics server logs
kubectl logs -n keda -l app=keda-metrics-apiserver --since=30m > /tmp/keda-metrics.log

# ScaledObject YAML (current state)
kubectl get scaledobject -n platform -o yaml > /tmp/scaledobjects.yaml

# HPA state
kubectl get hpa -n platform -o yaml > /tmp/hpa.yaml

# Recent events in the platform namespace
kubectl get events -n platform --sort-by='.lastTimestamp' | tail -50 > /tmp/events.txt

# Package for escalation
tar -czf keda-debug-$(date +%Y%m%d-%H%M%S).tar.gz /tmp/keda-*.log /tmp/scaledobjects.yaml /tmp/hpa.yaml /tmp/events.txt
```
