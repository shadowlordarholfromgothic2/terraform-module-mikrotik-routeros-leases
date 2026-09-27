# What the module sends to the provider, and what it hands back.
#
# The provider is mocked: the real one opens a REST connection to the router
# when it is configured, so even `command = plan` needs a reachable MikroTik
# otherwise. Every attribute asserted below comes from configuration rather
# than from the router, so mocking costs no coverage here. Anything that
# depends on a RouterOS response — a lease's `.id`, `dynamic`, `status` — is
# deliberately not asserted, because the mock invents those values.
mock_provider "routeros" {}

run "normalizes_mac_and_wires_every_field" {
  command = plan

  variables {
    server = "defconf"
    hosts = {
      # Written lowercase on purpose: RouterOS uppercases MACs, so a module
      # that passed this through unchanged would produce a diff on every plan.
      cp-1 = {
        ip      = "192.168.88.11"
        mac     = "bc:24:11:00:00:01"
        comment = "talos control plane 1"
      }
      # Mixed case, and no comment: `comment` is optional and must arrive null
      # rather than an empty string, which RouterOS would store as a comment.
      nas = {
        ip  = "192.168.88.30"
        mac = "Bc:24:11:00:00:0a"
      }
    }
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["cp-1"].mac_address == "BC:24:11:00:00:01"
    error_message = "A lowercase MAC must be uppercased before it reaches the provider."
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["nas"].mac_address == "BC:24:11:00:00:0A"
    error_message = "A mixed-case MAC must be uppercased before it reaches the provider."
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["cp-1"].address == "192.168.88.11"
    error_message = "address must be the host's ip, verbatim."
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["cp-1"].comment == "talos control plane 1"
    error_message = "comment must be passed through."
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["nas"].comment == null
    error_message = "An omitted comment must stay null, not become an empty string."
  }

  assert {
    condition     = alltrue([for l in routeros_ip_dhcp_server_lease.host : l.server == "defconf"])
    error_message = "Every lease must be bound to var.server."
  }
}

# The map key is a state address only. It must not leak into anything RouterOS
# stores, or renaming a host would be a router-visible change rather than just
# a state move.
run "map_key_does_not_reach_the_router" {
  command = plan

  variables {
    server = "defconf"
    hosts = {
      some-host-name = {
        ip  = "192.168.88.11"
        mac = "BC:24:11:00:00:01"
      }
    }
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["some-host-name"].comment == null
    error_message = "The map key must not be used as a fallback comment."
  }
}

run "server_defaults_to_unbound" {
  command = plan

  variables {
    hosts = {
      cp-1 = { ip = "192.168.88.11", mac = "BC:24:11:00:00:01" }
    }
  }

  assert {
    condition     = routeros_ip_dhcp_server_lease.host["cp-1"].server == null
    error_message = "Omitting server must leave the lease unbound, not invent a server name."
  }
}

run "empty_hosts_creates_nothing" {
  command = plan

  variables {
    server = "defconf"
    hosts  = {}
  }

  assert {
    condition     = length(routeros_ip_dhcp_server_lease.host) == 0
    error_message = "An empty hosts map must create no leases."
  }

  assert {
    condition     = output.leases == {}
    error_message = "An empty hosts map must produce an empty leases output."
  }
}

run "output_is_keyed_by_host_name" {
  command = plan

  variables {
    server = "defconf"
    hosts = {
      cp-1 = { ip = "192.168.88.11", mac = "bc:24:11:00:00:01" }
      nas  = { ip = "192.168.88.30", mac = "bc:24:11:00:00:0a" }
    }
  }

  assert {
    condition     = toset(keys(output.leases)) == toset(["cp-1", "nas"])
    error_message = "The leases output must be keyed by the hosts map keys."
  }

  assert {
    condition     = output.leases["cp-1"].address == "192.168.88.11"
    error_message = "The leases output must carry each lease's address."
  }

  # The output documents itself as returning the MAC as RouterOS stores it.
  assert {
    condition     = output.leases["cp-1"].mac == "BC:24:11:00:00:01"
    error_message = "The leases output must expose the uppercased MAC."
  }
}
