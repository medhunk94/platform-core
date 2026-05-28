resource "azurerm_postgresql_server" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password

  sku_name   = var.sku_name
  version    = var.postgresql_version
  storage_mb = var.storage_mb

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled
  auto_grow_enabled            = var.auto_grow_enabled

  public_network_access_enabled = var.subnet_id == null ? true : false
  ssl_enforcement_enabled       = var.ssl_enforcement_enabled
  ssl_minimal_tls_version_enforced = "TLS1_2"

  tags = var.tags
}

# Firewall rule to allow Azure services (if public access)
resource "azurerm_postgresql_firewall_rule" "allow_azure_services" {
  count               = var.subnet_id == null ? 1 : 0
  name                = "AllowAzureServices"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_postgresql_server.this.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# VNet integration (if subnet provided)
resource "azurerm_postgresql_virtual_network_rule" "vnet_rule" {
  count               = var.subnet_id != null ? 1 : 0
  name                = "${var.name}-vnet-rule"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_postgresql_server.this.name
  subnet_id           = var.subnet_id
}
