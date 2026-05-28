variable "name" {
  description = "Subnet name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "virtual_network_name" {
  description = "VNet name"
  type        = string
}

variable "address_prefixes" {
  description = "Subnet address prefixes"
  type        = list(string)
}

variable "service_endpoints" {
  description = "Service endpoints for subnet"
  type        = list(string)
  default     = []
}
