# Terraform Infrastructure

Infrastructure as code for Azure AKS platform using modular blueprints pattern.

## What I Learned

Built a scalable Terraform design from scratch that handles real-world requirements: multiple teams, multiple environments, and growing infrastructure needs. The key insight was **composition over duplication** - instead of copying code for each environment, I built reusable blueprints that compose together.

The blueprints pattern lets you scale in three dimensions:
- **Teams**: Add new microservices teams without touching infrastructure code
- **Services**: Deploy additional databases, storage, or compute resources by referencing existing blueprints
- **Environments**: Spin up dev/staging/prod with different configurations but same modules

## Architecture Benefits

**Blueprints Pattern**: Each blueprint is a self-contained module (VNet, AKS, PostgreSQL). Environments compose blueprints together using module references. This means you write infrastructure code once and reuse it everywhere.

**No Shared Config Files**: Backend configuration lives in each environment's `versions.tf`. This avoids the anti-pattern of shared config files that create tight coupling between environments.

**VNet Integration**: AKS and PostgreSQL both integrate into the VNet using subnet delegation and service endpoints. This gives private communication between cluster and databases without exposing them to the internet.

**Auto-Scaling Built-In**: AKS cluster scales from 2-5 nodes automatically based on workload. PostgreSQL has auto-growing storage. No manual intervention needed.

## Security Practices

**Secrets Management**: Database passwords and sensitive values are **never stored in code or tfvars files**. Instead, we use Azure Key Vault data sources to retrieve secrets at runtime:

```hcl
data "azurerm_key_vault" "platform_secrets" {
  name                = "platform-kv-${var.environment}"
  resource_group_name = "platform-shared-rg"
}

data "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  key_vault_id = data.azurerm_key_vault.platform_secrets.id
}

module "postgresql" {
  administrator_password = data.azurerm_key_vault_secret.postgres_password.value
  # ...
}
```

This approach means:
- No credentials in Git history
- No secrets on local machines or in CI/CD variables
- Centralized secret rotation in Key Vault
- Access control via Azure RBAC (only authorized identities can read secrets)

**Network Security**: PostgreSQL is VNet-integrated and not publicly accessible. AKS pods communicate with the database over private IPs within the VNet. No internet exposure for sensitive data services.

## Terraform Concepts Implemented

### Modules
Every blueprint is a Terraform module with standardized structure:
```
blueprints/
  ├── aks/          # Module for AKS cluster
  ├── postgresql/   # Module for PostgreSQL
  ├── vnet/         # Module for virtual networks
  └── ...
```

Each module has:
- `variables.tf`: Input parameters with validation
- `main.tf`: Resource definitions
- `outputs.tf`: Values exposed to calling module

### Remote State
Backend configured with Azure Storage for team collaboration:
```hcl
backend "azurerm" {
  resource_group_name  = "tfstate-rg"
  storage_account_name = "tfstateplatformdev"
  key                  = "dev.terraform.tfstate"
}
```

### Resource Dependencies
Using output-to-input chaining to create proper dependency graph:
```hcl
module "aks_subnet" {
  vnet_id = module.vnet.vnet_id  # AKS subnet depends on VNet
}

module "aks" {
  vnet_subnet_id = module.aks_subnet.id  # AKS depends on subnet
}
```

Terraform automatically determines the correct creation order.

### Conditional Resources
PostgreSQL VNet integration uses count to make resources optional:
```hcl
resource "azurerm_postgresql_virtual_network_rule" "this" {
  count     = var.subnet_id != null ? 1 : 0  # Only create if subnet provided
  subnet_id = var.subnet_id
}
```

This lets the same module work for both public and VNet-private databases.

### Built-in Functions
Used throughout for dynamic configuration:
- `merge()`: Combining default tags with custom tags
- `lookup()`: Safe defaults for optional variables
- Interpolation: `"${var.environment}-${var.name}"` for naming

### Data Sources
Retrieving existing Azure resources without managing them:
```hcl
data "azurerm_client_config" "current" {}  # Get current Azure tenant/subscription

data "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  key_vault_id = data.azurerm_key_vault.platform_secrets.id
}
```

Critical for security - read secrets from Key Vault at runtime instead of storing in code.

### Resource Lifecycle
AKS cluster uses lifecycle rules to prevent destructive changes:
```hcl
lifecycle {
  ignore_changes = [default_node_pool[0].node_count]  # Allow auto-scaler to manage count
}
```

### Azure-Specific Features
- **Managed Identity**: SystemAssigned identity for AKS (no credential management needed)
- **Azure CNI**: Pods get VNet IP addresses directly
- **Network Policy**: Calico for pod-to-pod firewall rules
- **Service Endpoints**: Direct path from subnet to Azure services (Storage, SQL)

## Project Structure
```
terraform/
  ├── blueprints/           # Reusable modules
  │   ├── aks/
  │   ├── nsg/
  │   ├── postgresql/
  │   ├── resource-group/
  │   ├── subnet/
  │   └── vnet/
  └── environments/
      └── dev/              # Dev environment composition
          ├── main.tf       # Composes blueprints
          └── versions.tf   # Provider and backend config
```

## How It Scales

**New Environment**: Copy `environments/dev/` to `environments/staging/`, change backend key and variable values. Same blueprints, different configuration.

**New Service**: Add another module reference in environment's `main.tf`. Example - adding Redis:
```hcl
module "redis" {
  source = "../../blueprints/redis"
  # ... configuration
}
```

**New Region**: Set `location = "eastus"` in environment variables. All resources deploy to new region.
