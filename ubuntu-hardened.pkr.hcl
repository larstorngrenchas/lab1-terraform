packer {
  required_plugins {
    googlecompute = {
      source  = "://github.com"
      version = "~> 1.1.4"
    }
  }
}

source "googlecompute" "hardened-ubuntu" {
  project_id   = "chas-devsecops-2026"
  source_image_family = "ubuntu-2204-lts"
  zone         = "europe-west1-b"
  image_name   = "hardened-ubuntu-{{timestamp}}"
  image_family = "hardened-ubuntu"
  ssh_username = "ubuntu"
  machine_type = "e2-medium"

  # Lägg till en extra disk för partitionerna (t.ex. 10GB)
  disk_size = 20
  
  # Skicka med cloud-init för att sköta partitioneringen vid boot
  metadata = {
    user-data = file("cloud-init.yaml")
  }
}

build {
  sources = ["source.googlecompute.hardened-ubuntu"]

  # Här kör vi din befintliga startup.sh
  provisioner "shell" {
    script = "startup.sh"
  }

  # 2. Kör Lynis inuti imagen
  # Vi lägger till || true för att Packer ska fortsätta även om Lynis har anmärkningar
  provisioner "shell" {
    inline = [
      "sudo lynis audit system --quick --no-colors > /tmp/lynis-report.txt || true",
      "sudo mv /tmp/lynis-report.txt /var/log/lynis-report.txt"
    ]
  }
}
