# KEDA Common Issues and Fixes

A quick-reference guide. For step-by-step diagnosis, see [runbook.md](./runbook.md).

---

## Issue 1: ScaledObject `Ready: False` — "ScaleTarget Not Found"

**Symptom:**
```
kubectl get scaledobject -n platform
NAME                           READY   ACTIVE
order-processor-scaledobject   False   False
```

**Cause:**  
The `scaleTargetRef.name` points to a Deployment that does not exist in the namespace.

**Fix:**
```bash
# Verify the Deployment exists
kubectl get deployment order-processor -n platform

# If missing, apply it first, then re-apply the ScaledObject
kubectl apply -f deployment.yaml
kubectl apply -f manifests/kafka-scaledobject.yaml
```

---

## Issue 2: HPA not scaling — "FailedGetExternalMetric"

**Symptom:**
```
kubectl describe hpa order-processor-hpa -n platform
# Events:
#   Warning  FailedGetExternalMetric  unable to get external metric ... no metrics returned from external metrics API
```

**Cause:**  
`keda-metrics-apiserver` is not returning the metric. Either the scaler can't reach  
the external source, or the ScaledObject's trigger is misconfigured.

**Fix:**
```bash
# 1. Check APIService health
kubectl get apiservice v1beta1.external.metrics.k8s.io

# 2. Query the metric directly
kubectl get --raw \
  "/apis/external.metrics.k8s.io/v1beta1/namespaces/platform/s0-kafka-platform-events" \
  | jq .

# 3. Check operator logs for connection errors
kubectl logs -n keda -l app=keda-operator --since=5m | grep -i "error\|kafka"
```

---

## Issue 3: Kafka scaler reports 0 lag but messages are piling up

**Cause A:** Wrong `consumerGroup` name.
```bash
# List actual consumer groups
kafka-consumer-groups.sh --bootstrap-server kafka-broker:9092 --list

# Compare with what's in your ScaledObject
kubectl get scaledobject order-processor-scaledobject -n platform \
  -o jsonpath='{.spec.triggers[0].metadata.consumerGroup}'
```

**Cause B:** Consumer group has never committed offsets (new group).  
KEDA reads committed offsets. A group that has never consumed has no offsets,  
so lag appears as 0 even with thousands of messages.
```bash
# Check if offsets are committed
kafka-consumer-groups.sh --bootstrap-server kafka-broker:9092 \
  --describe --group order-processor-consumer-group
# If output shows "no data available", the group has no history
# Fix: run one consumer from the group to commit an initial offset
```

**Cause C:** `offsetResetPolicy: latest` with a brand-new consumer group.  
New groups start at the latest offset — existing messages are not counted as lag.
```bash
# Change to "earliest" if you want to process all existing messages
# metadata:
#   offsetResetPolicy: earliest
```

---

## Issue 4: Pods not scaling to zero despite empty queue

**Most common cause:** `minReplicaCount: 1` (this is intentional — cold start protection).

**To enable scale-to-zero:**
```yaml
spec:
  minReplicaCount: 0   # change from 1 to 0
```

**If `minReplicaCount: 0` is already set:**
```bash
# Is cooldownPeriod still running?
kubectl describe scaledobject <name> -n platform
# Look for "Last Active Time" — pods won't scale down until cooldownPeriod seconds have passed

# Is the ScaledObject manually paused?
kubectl get scaledobject <name> -n platform \
  -o jsonpath='{.metadata.annotations}' | jq .
# Check for: "autoscaling.keda.sh/paused-replicas"

# Are there still messages in the queue? (Kafka)
kafka-consumer-groups.sh --bootstrap-server kafka-broker:9092 \
  --describe --group order-processor-consumer-group
```

---

## Issue 5: KEDA scaled Deployment that has a separate HPA

**Symptom:** Replica count oscillates. Two things are fighting over the Deployment.

**Cause:** There is both a KEDA-managed HPA and a manually created HPA targeting  
the same Deployment.

**Fix:**
```bash
# Find all HPAs targeting the Deployment
kubectl get hpa -n platform | grep order-processor

# Delete the manually created one — keep only the KEDA-managed one
kubectl delete hpa <manual-hpa-name> -n platform
```

KEDA names its HPA according to `advanced.horizontalPodAutoscalerConfig.name`.  
If not specified, it defaults to `keda-hpa-<scaledobject-name>`.

---

## Issue 6: `admission webhook denied` when applying ScaledObject

**Symptom:**
```
Error from server: error when creating "kafka-scaledobject.yaml":
admission webhook "vke.kedacore.io" denied the request:
ScaledObject.keda.sh "order-processor-scaledobject" is invalid:
...
```

**Common reasons:**

| Error message | Fix |
|---|---|
| `spec.minReplicaCount must be less than or equal to spec.maxReplicaCount` | Ensure `minReplicaCount ≤ maxReplicaCount` |
| `scaleTargetRef does not exist` | Apply the Deployment before the ScaledObject |
| `duplicate scaledobject targeting the same deployment` | Delete the existing ScaledObject first |
| `unknown trigger type: Kafka` | Use lowercase: `kafka` not `Kafka` |

---

## Issue 7: Cron ScaledObject not firing at expected time

**Symptom:** Deployment does not scale up at the cron time.

**Diagnosis:**
```bash
kubectl describe scaledobject etl-worker-cron-scaledobject -n platform
# Look for: "Next trigger at" in the status section

# Check operator logs around the expected fire time
kubectl logs -n keda -l app=keda-operator --since=5m | grep -i cron
```

**Common causes:**

| Cause | Fix |
|---|---|
| Wrong timezone | Use `timezone: UTC` and adjust times accordingly |
| Cron expression is off by one | Validate at crontab.guru with your exact expression |
| Operator pod restarted during the scheduled window | The Cron trigger may miss if the operator was down at fire time |
| ScaledObject was paused | Check `autoscaling.keda.sh/paused-replicas` annotation |

---

## Issue 8: Prometheus scaler returning "no data"

**Symptom:** ScaledObject is Active=False even though the PromQL query returns data in Grafana.

**Diagnosis:**
```bash
# Test from inside the cluster (not from your laptop)
kubectl run prom-test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(payment_events_total{risk_level="high"}[2m]))' \
  | python3 -m json.tool
```

**Common causes:**

| Cause | Fix |
|---|---|
| `serverAddress` is wrong (external URL vs in-cluster DNS) | Use in-cluster service DNS: `http://prometheus.monitoring.svc.cluster.local:9090` |
| Prometheus requires auth but `TriggerAuthentication` not set | Add `authenticationRef` and create `TriggerAuthentication` |
| Query returns a vector, not a scalar | Wrap with `sum(...)` to collapse to single value |
| Metric doesn't exist yet | Verify metric name with Prometheus `api/v1/label/__name__/values` |
| Time window too short (`[30s]`) | Use `[2m]` minimum for `rate()` to avoid empty windows |
