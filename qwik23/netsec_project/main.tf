resource "google_compute_network" "vpcs" {
  for_each = toset([ "ext", "int", "hasync", "mgmt" ])

  name = "vpc-${each.value}"
  auto_create_subnetworks = false
  project = var.gcp_project_id
}

resource "google_compute_subnetwork" "subnets" {
  for_each = {
    ext : "172.20.0.0/24"
    int : "172.20.1.0/24"
    hasync: "172.20.2.0/24"
    mgmt : "172.20.3.0/24"
  }
  name          = each.key
  ip_cidr_range = each.value
  region        = var.gcp_region
  network       = google_compute_network.vpcs[each.key].self_link
  project = var.gcp_project_id
}
