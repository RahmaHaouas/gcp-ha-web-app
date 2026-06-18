# Global and static public IP for the Load Balancer
resource "google_compute_global_address" "lb_ip" {
  name = "ha-lb-ip"
}

# Cloud Armor: basic security policy (WAF)
resource "google_compute_security_policy" "armor" {
  name = "ha-armor-policy"

  # Example rule: rate limiting per IP (simple anti-abuse protection)
  rule {
    action   = "rate_based_ban"
    priority = 1000

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      ban_duration_sec = 600
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
    }
  }

  # Mandatory default rule
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config { src_ip_ranges = ["*"] }
    }
  }
}

# Backend service: connects the LB to the MIG via the health check
resource "google_compute_backend_service" "web" {
  name                  = "web-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.web.id]
  security_policy       = google_compute_security_policy.armor.id

  backend {
    group           = google_compute_region_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# URL map: routes all traffic to the backend
resource "google_compute_url_map" "web" {
  name            = "web-url-map"
  default_service = google_compute_backend_service.web.id
}

# Target HTTP Proxy
resource "google_compute_target_http_proxy" "web" {
  name    = "web-http-proxy"
  url_map = google_compute_url_map.web.id
}

# Forwarding rule: public entry point on port 80
resource "google_compute_global_forwarding_rule" "web" {
  name                  = "web-forwarding-rule"
  target                = google_compute_target_http_proxy.web.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
