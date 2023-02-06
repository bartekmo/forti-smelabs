resource "google_compute_network" "tier1" {
  name = "vpc-tier1"
  auto_create_subnetworks = false
  project = var.gcp_project_id
}

resource "google_compute_network" "tier2" {
  name = "vpc-tier2"
  auto_create_subnetworks = false
  project = var.gcp_project_id
}

resource "google_compute_subnetwork" "tier1" {
  name          = "frontend"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.tier1.self_link
  project = var.gcp_project_id
}

resource "google_compute_subnetwork" "tier2" {
  name          = "backend"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.gcp_region
  network       = google_compute_network.tier2.self_link
  project = var.gcp_project_id
}

resource "google_compute_firewall" "front" {
  project     = var.gcp_project_id
  name        = "allow-http-frontend"
  network     = google_compute_network.tier1.self_link

  allow {
    protocol  = "tcp"
    ports     = ["80", "22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "back" {
  project     = var.gcp_project_id
  name        = "allow-http-backend"
  network     = google_compute_network.tier2.self_link

  allow {
    protocol  = "tcp"
    ports     = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "frontend" {
  zone = var.gcp_zone
  project = var.gcp_project_id
  name = "wrkld-frontend-vm"
  machine_type = "e2-standard-2"
  tags = ["frontend"]
  boot_disk {
    initialize_params {
      image              = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    }
  }
  network_interface {
    subnetwork           = google_compute_subnetwork.tier1.id
    network_ip           = "10.0.1.2"
    access_config {}
  }
  metadata = {
    startup-script = file("./startup-script-frontend.tpl")
  }
}

resource "google_compute_instance" "backend" {
  zone = var.gcp_zone
  project = var.gcp_project_id
  name = "wrkld-backend-vm"
  machine_type = "e2-standard-2"
  tags = ["backend"]
  boot_disk {
    initialize_params {
      image              = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    }
  }
  network_interface {
    subnetwork           = google_compute_subnetwork.tier2.id
    network_ip           = "10.0.2.2"
    access_config {}
  }
  metadata_startup_script = file("./startup-script-backend.sh")

  metadata = {
    app-code = filebase64("./app.tar.gz")
  }
}
