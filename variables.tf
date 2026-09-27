# This module deliberately knows nothing about Talos, Proxmox or clusters: it
# takes a map of hosts and makes static DHCP reservations for them. Callers
# project their own inventory into `hosts`, which keeps the module reusable for
# anything else on the same router.

variable "hosts" {
  description = "Static DHCP reservations to create, keyed by a stable name. The key is only an address in OpenTofu state; RouterOS identifies a lease by its MAC address."
  type = map(object({
    ip      = string
    mac     = string
    comment = optional(string)
  }))

  validation {
    condition = alltrue([
      for h in var.hosts : can(cidrnetmask("${h.ip}/32"))
    ])
    error_message = "Each host needs an IPv4 address without a prefix."
  }
  validation {
    # Second nibble even: a unicast address, which is the only kind a DHCP
    # client can present as its CHADDR.
    condition = alltrue([
      for h in var.hosts : can(regex("^[0-9A-Fa-f][02468AaCcEe](:[0-9A-Fa-f]{2}){5}$", h.mac))
    ])
    error_message = "Each host needs a unicast MAC address in aa:bb:cc:dd:ee:ff form."
  }
  validation {
    condition = (
      length(distinct([for h in var.hosts : h.ip])) == length(var.hosts) &&
      length(distinct([for h in var.hosts : lower(h.mac)])) == length(var.hosts)
    )
    error_message = "IP addresses and MAC addresses must each be unique across hosts."
  }
}

variable "server" {
  description = "Name of the RouterOS DHCP server the leases belong to, as shown by `/ip/dhcp-server/print` (`defconf` on a stock MikroTik configuration). Null leaves the lease unbound, which matches any server — fine with a single DHCP server, ambiguous once VLANs each have their own."
  type        = string
  default     = null

  validation {
    condition     = var.server == null ? true : trimspace(var.server) == var.server && var.server != ""
    error_message = "server must be null or a non-empty DHCP server name without surrounding whitespace."
  }
}
