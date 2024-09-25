provider "google" {
  project = "calm-photon-436315-j1"
  region  = var.region
  zone    = var.zone
}

variable "region" {
  description = "The region where resources will be deployed"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone within the region where the VM will be created"
  type        = string
  default     = "us-central1-a"
}

# Reserve a static external IP address for the VM
resource "google_compute_address" "static_ip" {
  name   = "jenkins-sonarqube-static-ip"
  region = var.region
}

# Define the GCP VM instance for Jenkins and SonarQube
resource "google_compute_instance" "jenkins_vm" {
  name         = "jenkins-sonarqube-vm"
  machine_type = "n2-standard-2"
  zone         = var.zone

  # Define the boot disk
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"  # Ubuntu 20.04
      size  = 50  # Disk size in GB
    }
  }

  # Define the network interface and attach the reserved static IP
  network_interface {
    network = "default"

    access_config {
      # Use the reserved static IP
      nat_ip = google_compute_address.static_ip.address
    }
  }

  # Add firewall rule for SSH, HTTP (for Jenkins and SonarQube)
  metadata = {
    ssh-keys = "mouhib:${file("~/.ssh/id_rsa.pub")}"
  }

  # Startup script for installing Jenkins and SonarQube
  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update

    # Install Java (required by Jenkins)
    sudo apt-get install -y openjdk-11-jdk

    # Install Jenkins
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
    /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y jenkins

    # Start and enable Jenkins service
    sudo systemctl start jenkins
    sudo systemctl enable jenkins

    # Install Docker and Docker Compose for SonarQube
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-compose

    # Install SonarQube Docker container
    sudo docker run -d -p 9000:9000 --name sonarqube sonarqube:latest
  EOT

  tags = ["jenkins", "sonarqube"]

  # Define the VM service account (adjust IAM roles as needed)
  service_account {
    email  = google_service_account.jenkins_sa.email
    scopes = ["cloud-platform"]
  }
}

# Firewall rule for allowing HTTP (8080, 9000) and SSH
resource "google_compute_firewall" "default" {
  name    = "allow-jenkins-sonarqube-traffic"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "9000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jenkins", "sonarqube"]
}

# Service account for the VM
resource "google_service_account" "jenkins_sa" {
  account_id   = "jenkins-sonarqube-sa"
  display_name = "Jenkins and SonarQube Service Account"
}

# Output the static external IP of the VM
output "vm_external_ip" {
  value = google_compute_address.static_ip.address
}

