# terraform-module-mikrotik-routeros-leases

Creates static DHCP reservations on a [MikroTik RouterOS](https://help.mikrotik.com/docs/spaces/ROS/pages/24805500/DHCP)
router — one `/ip/dhcp-server/lease` entry per host — from a map of hosts you
supply. It returns the created leases keyed by the same names you passed in,
including the RouterOS internal ID of each one, so a caller can reference a
lease it just created without reading it back.

The module deliberately knows nothing about *what* the hosts are: no cluster, no
hypervisor, no naming scheme. It takes a map of `{ ip, mac, comment }` and makes
reservations for it, which keeps it reusable for every other device on the same
router. Consequently it exposes nothing else the lease resource can do — no
lease times, rate limits, address lists, or DHCP options. The size of the
`hosts` map is the only thing that decides how much it creates; an empty map is
valid and creates nothing.

## What it does

1. Iterates `var.hosts` with `for_each`, so the map key becomes the resource
   instance address in state and one lease is created per entry.
2. Uppercases each `mac` before sending it, because RouterOS stores and returns
   MAC addresses uppercased — writing `bc:24:11:aa:bb:cc` in your inventory
   would otherwise produce a permanent diff.
3. Binds every lease to the DHCP server named in `var.server`, or leaves it
   unbound when that is `null`.
4. Sets each lease's `comment` from `each.value.comment`, which is the only
   field a human reading `/ip/dhcp-server/lease/print` has to go on.

## Requirements

| Name | Version |
| --- | --- |
| terraform / opentofu | `>= 1.9.0, < 2.0.0` |
| [routeros](https://registry.terraform.io/providers/terraform-routeros/routeros) | `1.99.1` |

The provider is pinned exactly rather than with a range. The
`terraform-routeros/routeros` schema tracks RouterOS itself and gains and
renames resource attributes between minor releases, so a floating constraint
turns an unrelated `init` into an unplanned schema change. The cost is real:
a root module that also calls another module pinning a different exact version
cannot resolve, so lift this to `~> 1.99` if you hit that. See
[Baked-in decisions](#baked-in-decisions).

This module declares no `provider` blocks — it inherits the configured instances
from the root module, which is where the router's credentials belong.

### Environment prerequisites

- **A reachable RouterOS device and credentials for it**, configured on the
  `routeros` provider in the root module. The account needs the `write` policy
  in addition to `read` and `api` (or `rest-api`); a read-only account fails at
  apply, not at plan.
- **The DHCP server named in `var.server` must already exist.** The module does
  not create DHCP servers, pools or networks. Check the name with
  `/ip/dhcp-server/print` — it is `defconf` on a stock configuration.
- **Every `ip` must be inside the network that DHCP server serves.** Nothing in
  this module can check that, and RouterOS will accept a reservation for an
  address the server cannot hand out; the client simply never gets it.
- **No hand-made static lease may already exist for the same MAC.** RouterOS
  rejects a duplicate static entry, so the apply fails. Import it instead — see
  [Lifecycle notes](#lifecycle-notes).
- **Addresses should sit outside the dynamic pool**, or at least be understood to
  be reserved. A reservation inside the pool works, but the pool can hand the
  same address to a different client before this host asks for it.

## Usage

Illustrative, not minimal — the MAC addresses below are Proxmox-range examples
and must be replaced with the real ones. A complete, runnable version of this is
in [examples/basic](examples/basic).

Pin `?ref=` to a tag that exists — `git ls-remote --tags origin` lists them.
Release automation does not rewrite the `?ref=` pins in this file, so treat the
version below as an example rather than as the current release.

```hcl
provider "routeros" {
  hosturl  = "https://192.168.88.1"
  username = "terraform"
  password = var.routeros_password
}

module "leases" {
  source = "github.com/shadowlordarholfromgothic2/terraform-module-mikrotik-routeros-leases?ref=v0.1.0"

  server = "defconf"

  hosts = {
    talos-cp-1 = {
      ip      = "192.168.88.11"
      mac     = "bc:24:11:00:00:01"
      comment = "talos control plane 1"
    }
    talos-worker-1 = {
      ip      = "192.168.88.21"
      mac     = "bc:24:11:00:00:02"
      comment = "talos worker 1"
    }
    nas = {
      ip  = "192.168.88.30"
      mac = "bc:24:11:00:00:03"
    }
  }
}
```

Projecting an existing inventory into `hosts` is the intended pattern, and keeps
the addressing decision in one place:

```hcl
module "leases" {
  source = "github.com/shadowlordarholfromgothic2/terraform-module-mikrotik-routeros-leases?ref=v0.1.0"

  server = "defconf"

  hosts = {
    for name, node in var.nodes : name => {
      ip      = node.address
      mac     = node.mac_address
      comment = "managed by opentofu — ${name}"
    }
  }
}
```

Confirm the router agrees with state after the first apply:

```console
$ tofu output -json leases
$ ssh admin@192.168.88.1 '/ip/dhcp-server/lease/print where !dynamic'
```

## Inputs

`server` has a default because a single-DHCP-server router does not need it.
`hosts` is required and has no sensible empty default worth reaching by
accident.

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `hosts` | Static DHCP reservations to create, keyed by a stable name. | `map(object({...}))` | n/a |
| `server` | Name of the RouterOS DHCP server the leases belong to. `null` leaves each lease unbound. | `string` | `null` |

### `hosts`

```hcl
map(object({
  ip      = string           # IPv4 address, no prefix — the address to reserve
  mac     = string           # unicast MAC, aa:bb:cc:dd:ee:ff form, any case
  comment = optional(string) # free text shown in /ip/dhcp-server/lease/print
}))
```

The map key is an address in OpenTofu state only — RouterOS never sees it and
identifies a lease by its MAC address. It must therefore be stable across
applies rather than derived from anything that churns; see
[Lifecycle notes](#lifecycle-notes) for what a rename costs.

Three validations run at plan time, before the provider is contacted:

| What it enforces | What it rejects |
| --- | --- |
| `ip` is a bare IPv4 address | `10.0.0.5/24`, `fd00::1`, `10.0.0.256`, `10.0.0`, `""` |
| `mac` is a unicast MAC in colon form | `bc-24-11-aa-bb-cc`, `bc:24:11:aa:bb`, and any multicast address including `ff:ff:ff:ff:ff:ff` and `01:00:5e:…` |
| `ip` and `mac` are each unique across the map | two hosts sharing an address, or the same MAC written in different cases |

Legal but a bad idea:

- **Leading zeros in `ip`.** `010.0.0.5` passes validation and is not treated as
  equal to `10.0.0.5` by the uniqueness check, so the same address can be
  reserved twice under two keys. Write addresses without leading zeros.
- **Addresses inside the dynamic pool** (see
  [Environment prerequisites](#environment-prerequisites)).
- **A `hosts` key derived from an index** (`node-0`, `node-1`). Removing the
  first entry then renumbers and recreates every lease after it.

Unicast is enforced because a multicast or broadcast MAC can never appear as a
DHCP client's `CHADDR`, so a reservation for one is dead configuration rather
than a working entry.

## Outputs

| Name | Description | Sensitive |
| --- | --- | --- |
| `leases` | Created reservations keyed by host name, each with `id` (the RouterOS internal `.id`, e.g. `*1A`), `address` and `mac` (as RouterOS stores it, uppercased). | no |

`mac` in the output is the uppercased form the router holds, not the form you
wrote in `hosts`. Compare case-insensitively if you feed it into anything else.

## Resources created

| Address | Purpose |
| --- | --- |
| `routeros_ip_dhcp_server_lease.host` | One static DHCP reservation per entry in `hosts`, keyed by the map key. |

## Baked-in decisions

- **MAC addresses are uppercased on the way in** — RouterOS normalises them
  anyway, and doing it here makes the module accept whatever case your inventory
  uses without producing a diff on every plan.
- **The lease resource's other fields are not exposed** — `lease_time`,
  `rate_limit`, `address_lists`, `dhcp_option`, `dhcp_option_set`,
  `always_broadcast`, `block_access`, `client_id`, `disabled`, `insert_queue_before`
  and `use_src_mac` are all left at the provider default. Each one is a per-host
  concern that would have to be added to the `hosts` object type; add the one
  you need rather than a passthrough map, so validation stays possible.
- **`server` is module-wide, not per host** — a module instance describes one
  DHCP server. Call the module once per server when a router has several, which
  also keeps each VLAN's reservations as a separate plan.
- **The provider version is an exact pin, not a range** — see
  [Requirements](#requirements) for the tradeoff.
- **No `lifecycle` blocks, no `prevent_destroy`** — a static reservation is cheap
  to recreate and destroying one does not take a host off the network
  immediately, so guarding it would cost more than it saves.

## Lifecycle notes

- **Renaming a `hosts` key destroys and recreates the lease.** The key is the
  `for_each` key, so a rename is a delete plus an add to OpenTofu, even though
  nothing about the reservation changed. Avoid the churn with a `moved` block in
  the calling configuration:

  ```hcl
  moved {
    from = module.leases.routeros_ip_dhcp_server_lease.host["talos-cp-1"]
    to   = module.leases.routeros_ip_dhcp_server_lease.host["cp-1"]
  }
  ```

- **A recreate is not an outage, but it is not instant either.** The client keeps
  the address it already holds until its lease expires, so removing and
  re-adding a reservation is invisible at the time of apply and only takes effect
  at the next renewal. Reboot the host or run `/ip/dhcp-server/lease/remove` on
  the dynamic entry if you need the new address now.
- **Changing a host's `ip` does not move the host.** The router will hand out the
  new address at the next renewal, which for a typical lease time can be hours
  away. Anything with the old address hardcoded — DNS, a kubeconfig, a peer list
  — has to be updated separately; this module does not know about it.
- **A lease the router already has must be imported, not applied over.** RouterOS
  refuses a second static entry for the same MAC, so the apply fails with a
  provider error rather than adopting it. Find the internal ID and import:

  ```console
  $ ssh admin@192.168.88.1 '/ip/dhcp-server/lease/print detail where mac-address="BC:24:11:00:00:01"'
  $ tofu import 'module.leases.routeros_ip_dhcp_server_lease.host["talos-cp-1"]' '*1A'
  ```

- **Dynamic leases are invisible to this module.** It manages only the static
  entries it created. A host that already has a dynamic lease for a different
  address keeps it until renewal, and `tofu plan` will not show that conflict.
- **A lease deleted by hand on the router comes back on the next apply**, which
  is usually what you want — but it means fixing a reservation in Winbox is
  temporary. Change `hosts` instead.
- **Destroying the module removes the reservations, not the addresses in use.**
  Hosts stay reachable on their current leases and drift to pool addresses over
  the following hours, which makes a `tofu destroy` here quietly delayed rather
  than obviously broken.

## Layout

| File | Contents |
| --- | --- |
| [variables.tf](variables.tf) | Inputs and all validation. |
| [main.tf](main.tf) | The lease resource. |
| [outputs.tf](outputs.tf) | The module's contract. |
| [versions.tf](versions.tf) | Terraform and provider constraints. |
| [tests/validation.tftest.hcl](tests/validation.tftest.hcl) | One run block per input the validation must reject. |
| [tests/leases.tftest.hcl](tests/leases.tftest.hcl) | What the module sends to the provider, and the shape of `leases`. |
| [examples/basic](examples/basic) | A runnable root module calling this one. |

## Development

Commits on `main` follow [Conventional
Commits](https://www.conventionalcommits.org/en/v1.0.0/): the subject prefix
decides the CHANGELOG section and the version bump. `feat:` and `fix:` are the
ones that produce a release; `chore:`, `style:` and `test:` are hidden from the
changelog.

- **Validate** (`.github/workflows/terraform-validate.yml`) runs on every pull
  request: `terraform fmt -check`, then `terraform validate`, `terraform test`
  and a validate of every directory under `examples/`, against both the version
  floor from [versions.tf](versions.tf) and the current release — all of it
  again under OpenTofu — plus `tflint` with [.tflint.hcl](.tflint.hcl). Run the
  same checks locally:

  ```console
  $ terraform fmt -recursive
  $ terraform init -backend=false && terraform validate
  $ terraform test
  $ terraform -chdir=examples/basic init -backend=false && terraform -chdir=examples/basic validate
  $ tflint --init && tflint -f compact --recursive
  ```

  `terraform test` needs no router and no credentials: both test files declare
  `mock_provider "routeros" {}`. That is not a stylistic choice — the real
  provider opens a REST connection to the router when it is *configured*, so
  even `command = plan` fails without one. The consequence is that anything
  whose value comes from a RouterOS response — a lease's `.id`, `dynamic`,
  `status` — cannot be asserted in these tests, and is not. What they do cover
  is every input the validation must reject, the MAC uppercasing, the wiring of
  each field, and the shape of the `leases` output.

  `examples/` is validated but never planned, for the same reason.

- **Release** (`.github/workflows/release.yml`) runs
  [release-please](https://github.com/googleapis/release-please) on `main`. It
  keeps a release PR open that accumulates `CHANGELOG.md` entries; merging that
  PR writes the changelog, bumps
  [.release-please-manifest.json](.release-please-manifest.json) and tags the
  release as `v<version>`. While the major version is `0`,
  `bump-minor-pre-major` turns a breaking change into a minor bump rather than
  `1.0.0`.

One thing to know about the `terraform-module` release type: on each release it
rewrites every string matching `v<major>.<minor>.<patch>` in
[versions.tf](versions.tf) to the new version, with no regard for what that
string means. Nothing there matches today — both `>= 1.9.0, < 2.0.0` and
`1.99.1` are written without a `v` prefix — but adding a `v`-prefixed version to
that file, in a comment or otherwise, would let a release silently rewrite the
provider pin. In README files the same release type rewrites only
`version = "~> X.Y"`, which is why the `?ref=` pins under
[Usage](#usage) are maintained by hand.
