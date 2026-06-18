resource "google_monitoring_uptime_check_config" "web" {
  display_name = "HA Web App - uptime"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path = "/"
    port = 80
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host = google_compute_global_address.lb_ip.address
    }
  }
}