output "resource_group_name" {
  description = "Resource group name"
  value       = module.resource_group.name
}

output "vnet_name" {
  description = "VNet name"
  value       = module.vnet.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.name
}

output "aks_kube_config" {
  description = "AKS kubeconfig"
  value       = module.aks.kube_config
  sensitive   = true
}

output "postgresql_fqdn" {
  description = "PostgreSQL FQDN"
  value       = module.postgresql.fqdn
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string"
  value       = module.postgresql.connection_string
  sensitive   = true
}
