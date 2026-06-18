# --- VPC personnalisé (pas de sous-réseaux auto) ---
resource "google_compute_network" "vpc" {
  name                    = "ha-vpc"
  auto_create_subnetworks = false
}

# --- Sous-réseau privé dans la région choisie ---
resource "google_compute_subnetwork" "subnet" {
  name          = "ha-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# --- Cloud Router + NAT : sortie internet pour des VM sans IP publique ---
resource "google_compute_router" "router" {
  name    = "ha-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "ha-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# --- Pare-feu : autoriser le trafic du Load Balancer et des health checks ---
# Ces plages d'IP appartiennent à l'infrastructure Google de health check / LB.
resource "google_compute_firewall" "allow_lb_health" {
  name    = "allow-lb-and-health-checks"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
}

# --- Pare-feu : SSH uniquement via IAP (pas de SSH exposé sur internet) ---
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Plage d'IP réservée à Identity-Aware Proxy
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["web"]
}

# --- Pare-feu : trafic interne entre les VM du VPC ---
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.id

  allow { protocol = "icmp" }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = ["10.0.0.0/24"]
}