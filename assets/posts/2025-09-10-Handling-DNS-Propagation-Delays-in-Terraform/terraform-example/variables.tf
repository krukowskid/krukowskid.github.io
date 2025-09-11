variable "subscription_id" {
  description = "The subscription ID where the resources will be created"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet where the private endpoint will be created"
  type        = string
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone to link with the private endpoint"
  type        = string
}
