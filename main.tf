resource "routeros_ip_dhcp_server_lease" "host" {
  for_each = var.hosts

  address = each.value.ip

  # RouterOS stores and returns MACs uppercased, so normalize on the way in to
  # keep plans empty regardless of how the caller writes them.
  mac_address = upper(each.value.mac)

  server  = var.server
  comment = each.value.comment
}
