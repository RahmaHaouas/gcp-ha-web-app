# Instance Model: VM without public IP, "web" tag, startup script
resource "google_compute_instance_template" "web" {
  name_prefix  = "web-template-"
  machine_type = "e2-small"
  tags         = ["web"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    # Aucune bloc access_config => pas d'IP publique (sortie via Cloud NAT)
  }

  metadata_startup_script = file("${path.module}/startup.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# Health check reused for both autohealing AND the LB backend
resource "google_compute_health_check" "web" {
  name                = "web-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# REGIONAL Managed Instance Group: VMs distributed across multiple zones
resource "google_compute_region_instance_group_manager" "web" {
  name               = "web-mig"
  region             = var.region
  base_instance_name = "web"

  version {
    instance_template = google_compute_instance_template.web.id
  }

  named_port {
    name = "http"
    port = 80
  }

  # Autohealing: if a VM fails the health check, the MIG recreates it
  auto_healing_policies {
    health_check      = google_compute_health_check.web.id
    initial_delay_sec = 90
  }
}

# Autoscaler: adjusts the number of VMs based on CPU load
resource "google_compute_region_autoscaler" "web" {
  name   = "web-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.web.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 5
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}