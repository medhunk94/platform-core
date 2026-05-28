variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "vnet_address_space" {
  description = "VNet address space"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "AKS subnet prefix"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "db_subnet_prefix" {
  description = "Database subnet prefix"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}

variable "aks_node_count" {
  description = "AKS initial node count"
  type        = number
  default     = 2
}

variable "aks_min_count" {
  description = "AKS minimum node count"
  type        = number
  default     = 2
}

variable "aks_max_count" {
  description = "AKS maximum node count"
  type        = number
  default     = 5
}

variable "aks_vm_size" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Project     = "platform-core"
  }
}
