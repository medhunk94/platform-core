variable "name" {
  description = "VNet name"
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

variable "address_space" {
  description = "VNet address space"
  type        = list(string)
}

variable "tags" {
  description = "Tags for VNet"
  type        = map(string)
  default     = {}
}
