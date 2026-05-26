# Commands to set up and test ESO

# 1. Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -n vault --create-namespace -f vault/values.yaml

# 2. Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=60s

# 3. Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace -f eso/values.yaml

# 4. Create secrets in Vault
kubectl exec -n vault vault-0 -- vault kv put secret/checkout/database password=superSecretDBPass123
kubectl exec -n vault vault-0 -- vault kv put secret/checkout/kafka password=kafkaPass456

# 5. Apply SecretStore and ExternalSecret
kubectl apply -f examples/secretstore.yaml
kubectl apply -f examples/externalsecret.yaml

# 6. Verify secret was created
kubectl get secret checkout-app-secrets -n checkout -o yaml
