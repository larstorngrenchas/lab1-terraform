# main.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_instance" "vm" {
  name         = "${var.student_id}-lab1-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-b"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {} # Ger VM:en en extern IP
  }

  metadata = {
    # Formatet ska vara: användarnamn:nyckelsträng
    # file() läser in din lokala publika nyckel när du kör terraform apply
    # 'ubuntu' är användarnamnet inuti VM:en
    ssh-keys = "ubuntu:${file("/Users/lasse/.ssh/id_ed25519.pub")}"
  }

  metadata_startup_script = file("startup.sh")

  labels = {
    student = var.student_id
    course  = "devsecops-2026"
    lab     = "1"
  }

  tags = ["lab1", "ssh"]
}

resource "google_compute_resource_policy" "daily_backup" {
  name   = "${var.student_id}-daily-backup"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "03:00"
      }
    }
    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "backup_attachment" {
  name = google_compute_resource_policy.daily_backup.name
  disk = google_compute_instance.vm.name
  zone = "${var.region}-b"
}

output "instance_external_ip" {
  description = "Den externa IP-adressen för din härdade VM"
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}