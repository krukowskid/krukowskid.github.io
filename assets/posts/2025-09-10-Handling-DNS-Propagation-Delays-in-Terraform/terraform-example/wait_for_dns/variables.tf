variable "dns_name" {
  description = "The DNS name to resolve"
  type        = string
}

variable "ip_address" {
  description = "The IP address that the DNS name should resolve to"
  type        = string
  validation {
    condition     = can(cidrnetmask("${var.ip_address}/32"))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "timeout_seconds" {
  description = "The number of seconds to wait for the correct DNS resolution"
  type        = number
  default     = 600
}

variable "sleep_seconds" {
  description = "The number of seconds to sleep between DNS resolution attempts"
  type        = number
  default     = 90
}

variable "triggers" {
  description = "A map of values that will be used to trigger the resource to recreate"
  type        = map(string)
  default     = {}
}

variable "successful_attempts" {
  description = "The number of successful DNS resolution attempts before considering the operation successful"
  type        = number
  default     = 10
}
