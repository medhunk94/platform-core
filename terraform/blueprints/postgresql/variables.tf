variable "name" {
  description = "PostgreSQL server name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "administrator_login" {
  description = "Admin username"
  type        = string
  default     = "psqladmin"
}

variable "administrator_password" {
  description = "Admin password"
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "SKU name (e.g., B_Gen5_1, GP_Gen5_2)"
  type        = string
  default     = "B_Gen5_1"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 5120
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups"
  type        = bool
  default     = false
}

variable "auto_grow_enabled" {
  description = "Enable storage auto-grow"
  type        = bool
  default     = true
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "11"
}

variable "ssl_enforcement_enabled" {
  description = "Enforce SSL connection"
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for PostgreSQL server"
  type        = map(string)
  default     = {}
}
