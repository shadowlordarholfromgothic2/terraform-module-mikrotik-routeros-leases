# Basic example

Three static DHCP reservations on a single RouterOS DHCP server, the smallest
complete call of this module: a configured `routeros` provider, a `hosts` map,
and the reserved addresses projected back out.

The addresses and MAC addresses here are placeholders on the stock MikroTik
`192.168.88.0/24` network. Replace them before running this anywhere real —
reserving an address for a MAC that does not exist is harmless, but reserving
one that is already in use by something else is not.

```console
$ export TF_VAR_router_password='...'
$ tofu init
$ tofu plan
```

`tofu plan` needs a reachable router: the provider opens a REST connection to
`var.router_url` when it is configured, before any resource is planned. CI
therefore runs `validate` against this directory but never `plan`. To exercise
the module without a router, use the tests in [../../tests](../../tests), which
mock the provider.

Every input has a default except `router_password`, so a run against a stock
router needs only that one variable.
