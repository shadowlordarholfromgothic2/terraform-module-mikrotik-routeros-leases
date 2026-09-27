output "leases" {
  description = "Created reservations keyed by host name, with the RouterOS internal ID of each lease."
  value = {
    for name, lease in routeros_ip_dhcp_server_lease.host :
    name => {
      id      = lease.id
      address = lease.address
      mac     = lease.mac_address
    }
  }
}
