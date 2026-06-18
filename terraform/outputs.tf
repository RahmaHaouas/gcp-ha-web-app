output "load_balancer_ip" {
  description = "IP publique du Load Balancer (ouvre-la dans un navigateur)"
  value       = google_compute_global_address.lb_ip.address
}