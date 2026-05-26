# External Secrets Operator (ESO)

Manages secrets from HashiCorp Vault without storing them in Git.

## Setup

1. Install Vault in dev mode
2. Install ESO operator
3. Create SecretStore pointing to Vault
4. Create ExternalSecret resources

## Why ESO?

- No plaintext secrets in Git
- Centralized secret management
- Auto-sync secrets to K8s
- Works with Vault, AWS Secrets Manager, Azure Key Vault, etc.

## Components

- **Vault**: Stores actual secrets
- **SecretStore**: Connection config to Vault
- **ExternalSecret**: Defines which secrets to pull
- **Secret**: Auto-created K8s secret by ESO
