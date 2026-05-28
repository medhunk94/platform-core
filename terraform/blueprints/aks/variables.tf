variable "name" {
  description = "AKS cluster name"
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

variable "dns_prefix" {
  description = "DNS prefix for AKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "default_node_pool" {
  description = "Default node pool configuration"
  type = object({
    name                = string
    node_count          = number
    vm_size             = string
    vnet_subnet_id      = string
    max_pods            = number
    enable_auto_scaling = bool
    min_count           = number
    max_count           = number
  })
}

variable "network_profile" {
  description = "Network profile configuration"
  type = object({
    network_plugin    = string
    network_policy    = string
    service_cidr      = string
    dns_service_ip    = string
    load_balancer_sku = string
  })
  default = {
    network_plugin    = "azure"
    network_policy    = "calico"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
    load_balancer_sku = "standard"
  }
}

variable "tags" {
  description = "Tags for AKS cluster"
  type        = map(string)
  default     = {}
}
