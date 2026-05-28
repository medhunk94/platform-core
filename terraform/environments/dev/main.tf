# Dev Environment - AKS Platform Infrastructure
# Designed for Azure deployment. Requires:
# - Key Vault "platform-kv-dev" in "platform-shared-rg" with secret "postgres-admin-password"
# - Storage account "tfstateplatformdev" for remote state (see versions.tf)

# Key Vault for secrets management (must exist before terraform apply)
data "azurerm_key_vault" "platform_secrets" {
  name                = "platform-kv-${var.environment}"
  resource_group_name = "platform-shared-rg"
}

data "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  key_vault_id = data.azurerm_key_vault.platform_secrets.id
}

# Resource Group
module "resource_group" {
  source   = "../../blueprints/resource-group"
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Virtual Network
module "vnet" {
  source              = "../../blueprints/vnet"
  name                = "platform-vnet-${var.environment}"
  resource_group_name = module.resource_group.name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# AKS Subnet
module "aks_subnet" {
  source               = "../../blueprints/subnet"
  name                 = "aks-subnet"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = var.aks_subnet_prefix
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql"]
}

# Database Subnet
module "db_subnet" {
  source               = "../../blueprints/subnet"
  name                 = "db-subnet"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = var.db_subnet_prefix
  service_endpoints    = ["Microsoft.Sql"]
}

# AKS Cluster
module "aks" {
  source              = "../../blueprints/aks"
  name                = "platform-aks-${var.environment}"
  resource_group_name = module.resource_group.name
  location            = var.location
  dns_prefix          = "platform-${var.environment}"
  kubernetes_version  = "1.28"

  default_node_pool = {
    name                = "default"
    node_count          = var.aks_node_count
    vm_size             = var.aks_vm_size
    vnet_subnet_id      = module.aks_subnet.id
    max_pods            = 110
    enable_auto_scaling = true
    min_count           = var.aks_min_count
    max_count           = var.aks_max_count
  }

  network_profile = {
    network_plugin    = "azure"
    network_policy    = "calico"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# PostgreSQL Database
module "postgresql" {
  source                         = "../../blueprints/postgresql"
  name                           = "platform-db-${var.environment}"
  resource_group_name            = module.resource_group.name
  location                       = var.location
  administrator_login            = "psqladmin"
  administrator_password         = data.azurerm_key_vault_secret.postgres_password.value
  sku_name                       = "B_Gen5_1"
  storage_mb                     = 5120
  postgresql_version             = "11"
  backup_retention_days          = 7
  geo_redundant_backup_enabled   = false
  auto_grow_enabled              = true
  ssl_enforcement_enabled        = true
  subnet_id                      = module.db_subnet.id
  tags                           = var.tags
}
