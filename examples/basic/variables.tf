variable "router_url" {
  description = "Base URL of the RouterOS REST API, including the scheme."
  type        = string
  default     = "https://192.168.88.1"
}

variable "router_username" {
  description = "RouterOS account to authenticate as. Needs the read, write and rest-api policies; a read-only account fails at apply rather than at plan."
  type        = string
  default     = "terraform"
}

variable "router_password" {
  description = "Password for var.router_username. Supply it via TF_VAR_router_password or a tfvars file that is not committed."
  type        = string
  sensitive   = true
}

variable "dhcp_server" {
  description = "Name of the DHCP server the reservations belong to, as shown by `/ip/dhcp-server/print`."
  type        = string
  default     = "defconf"
}
