provider "routeros" {
  hosturl  = var.router_url
  username = var.router_username
  password = var.router_password

  # A stock MikroTik serves the REST API with a self-signed certificate. Drop
  # this once the router presents a certificate the machine running OpenTofu
  # trusts.
  insecure = true
}

module "leases" {
  source = "../.."

  server = var.dhcp_server

  # The map keys are state addresses, not router data: keep them stable, and
  # avoid anything index-derived — removing one entry would otherwise renumber
  # and recreate every lease after it.
  hosts = {
    talos-cp-1 = {
      ip      = "192.168.88.11"
      mac     = "BC:24:11:00:00:01"
      comment = "talos control plane 1"
    }

    talos-worker-1 = {
      ip      = "192.168.88.21"
      mac     = "BC:24:11:00:00:02"
      comment = "talos worker 1"
    }

    # comment is optional; without one, /ip/dhcp-server/lease/print shows
    # nothing about why this reservation exists.
    nas = {
      ip  = "192.168.88.30"
      mac = "BC:24:11:00:00:0A"
    }
  }
}
