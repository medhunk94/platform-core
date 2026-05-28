output "id" {
  description = "PostgreSQL server ID"
  value       = azurerm_postgresql_server.this.id
}

output "name" {
  description = "PostgreSQL server name"
  value       = azurerm_postgresql_server.this.name
}

output "fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_server.this.fqdn
}

output "administrator_login" {
  description = "Administrator username"
  value       = azurerm_postgresql_server.this.administrator_login
}

output "connection_string" {
  description = "Connection string template"
  value       = "postgresql://${azurerm_postgresql_server.this.administrator_login}@${azurerm_postgresql_server.this.name}:PASSWORD@${azurerm_postgresql_server.this.fqdn}:5432/DATABASE_NAME?sslmode=require"
  sensitive   = true
}
