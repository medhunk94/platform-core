variable "name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags for resource group"
  type        = map(string)
  default     = {}
}
