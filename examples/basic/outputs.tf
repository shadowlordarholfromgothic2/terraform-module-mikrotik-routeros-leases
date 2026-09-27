output "leases" {
  description = "The reservations the module created, keyed by host name."
  value       = module.leases.leases
}

output "addresses" {
  description = "Reserved address per host name — the part a caller usually wants to feed into DNS or an inventory."
  value       = { for name, lease in module.leases.leases : name => lease.address }
}
