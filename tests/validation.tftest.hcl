# The input validation is the part of this module worth testing: it is pure
# expression evaluation, so it runs with no router and no credentials.
#
# The provider is mocked rather than omitted. Variable validation fails before
# any provider is configured, so these runs would pass without it — but if a
# validation ever stops rejecting what it should, the run would carry on into
# provider configuration and fail with a connection error instead of the
# "expected failure" message that actually explains what broke.
mock_provider "routeros" {}

variables {
  server = "defconf"
}

# --- hosts.ip ------------------------------------------------------------

run "rejects_ip_with_prefix" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11/24", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_ipv6" {
  command = plan

  variables {
    hosts = {
      a = { ip = "fd00::1", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_octet_out_of_range" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.256", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_truncated_ip" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_empty_ip" {
  command = plan

  variables {
    hosts = {
      a = { ip = "", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

# --- hosts.mac -----------------------------------------------------------

run "rejects_broadcast_mac" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "ff:ff:ff:ff:ff:ff" }
    }
  }

  expect_failures = [var.hosts]
}

# The IPv4 multicast MAC prefix — a DHCP client can never present one as its
# CHADDR, so a reservation for it is dead configuration.
run "rejects_multicast_mac" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "01:00:5e:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_dash_separated_mac" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "bc-24-11-00-00-01" }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_short_mac" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "bc:24:11:00:00" }
    }
  }

  expect_failures = [var.hosts]
}

# --- uniqueness ----------------------------------------------------------

run "rejects_duplicate_ip" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "BC:24:11:00:00:01" }
      b = { ip = "192.168.88.11", mac = "BC:24:11:00:00:02" }
    }
  }

  expect_failures = [var.hosts]
}

# Case must not be a way to smuggle the same MAC in twice: RouterOS would see
# one lease and the second apply would collide.
run "rejects_duplicate_mac_in_different_case" {
  command = plan

  variables {
    hosts = {
      a = { ip = "192.168.88.11", mac = "bc:24:11:00:00:01" }
      b = { ip = "192.168.88.12", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.hosts]
}

# --- server --------------------------------------------------------------

run "rejects_empty_server" {
  command = plan

  variables {
    server = ""
    hosts = {
      a = { ip = "192.168.88.11", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.server]
}

run "rejects_server_with_surrounding_whitespace" {
  command = plan

  variables {
    server = " defconf"
    hosts = {
      a = { ip = "192.168.88.11", mac = "BC:24:11:00:00:01" }
    }
  }

  expect_failures = [var.server]
}
