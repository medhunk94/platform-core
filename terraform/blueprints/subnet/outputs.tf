output "id" {
  description = "Subnet ID"
  value       = azurerm_subnet.this.id
}

output "name" {
  description = "Subnet name"
  value       = azurerm_subnet.this.name
}

output "address_prefixes" {
  description = "Subnet address prefixes"
  value       = azurerm_subnet.this.address_prefixes
}
