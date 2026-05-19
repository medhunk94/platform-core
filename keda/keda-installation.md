
## Installation

```bash
# Add the KEDA Helm repo
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA into its own namespace
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace

# Verify
kubectl get pods -n keda
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS
keda-operator-xxxxxxxxx-xxxxx             1/1     Running   0
keda-metrics-apiserver-xxxxxxxxx-xxxxx    1/1     Running   0
keda-admission-webhooks-xxxxxxxxx-xxxxx   1/1     Running   0
```

---

## Useful commands

```bash
# Check ScaledObject status and current replica count
kubectl get scaledobject -n platform

# Describe for event history and errors
kubectl describe scaledobject kafka-consumer-scaledobject -n platform

# Watch the HPA that KEDA created
kubectl get hpa -n platform -w

# Check current Kafka lag (requires kafka-consumer-groups.sh or kaf CLI)
kafka-consumer-groups.sh --bootstrap-server <broker> \
  --describe --group my-service-consumer-group
```

---

## Related files

| File | Purpose |
|---|---|
| [keda-scaledobject.yaml](keda-scaledobject.yaml) | ScaledObject for Kafka consumer lag-based scaling |
| [basic-hpa.yaml](basic-hpa.yaml) | Standard HPA for CPU/memory driven scaling |
| [custom-metrics-hpa.yaml](custom-metrics-hpa.yaml) | HPA using Prometheus custom metrics |
| [README.md](README.md) | General HPA overview and comparison of all three patterns |