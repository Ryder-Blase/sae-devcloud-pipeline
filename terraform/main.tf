terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

# VM pour GitLab (Gestion du code)
resource "proxmox_vm_qemu" "gitlab" {
  name        = "gitlab-vm"
  target_node = var.proxmox_node
  clone       = var.template_name
  agent       = 1
  os_type     = "cloud-init"
  memory      = var.gitlab_memory
  balloon     = 2048
  
  cpu {
    sockets = 1
    cores   = var.gitlab_cores
    type    = "host"
  }
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.storage_name
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size     = "100G"
          storage  = var.storage_name
          iothread = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = var.ip_mode == "dhcp" ? "ip=dhcp" : "ip=${var.gitlab_ip}/${var.netmask},gw=${var.gateway}"

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key
}

# VM pour infrastructure 1 (Master node)
resource "proxmox_vm_qemu" "infra1" {
  name        = "infra1-vm"
  target_node = var.proxmox_node
  clone       = var.template_name
  agent       = 1
  os_type     = "cloud-init"
  memory      = var.infra_memory
  balloon     = 1024
  
  cpu {
    sockets = 1
    cores   = var.infra_cores
    type    = "host"
  }
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.storage_name
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size     = "50G"
          storage  = var.storage_name
          iothread = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = var.ip_mode == "dhcp" ? "ip=dhcp" : "ip=${var.infra1_ip}/${var.netmask},gw=${var.gateway}"

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key
}

# VM pour infrastructure 2 (Worker node 1)
resource "proxmox_vm_qemu" "infra2" {
  name        = "infra2-vm"
  target_node = var.proxmox_node
  clone       = var.template_name
  agent       = 1
  os_type     = "cloud-init"
  memory      = var.infra_memory
  balloon     = 1024
  
  cpu {
    sockets = 1
    cores   = var.infra_cores
    type    = "host"
  }
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.storage_name
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size     = "50G"
          storage  = var.storage_name
          iothread = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = var.ip_mode == "dhcp" ? "ip=dhcp" : "ip=${var.infra2_ip}/${var.netmask},gw=${var.gateway}"

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key
}

# VM pour infrastructure 3 (Worker node 2)
resource "proxmox_vm_qemu" "infra3" {
  name        = "infra3-vm"
  target_node = var.proxmox_node
  clone       = var.template_name
  agent       = 1
  os_type     = "cloud-init"
  memory      = var.infra_memory
  balloon     = 1024
  
  cpu {
    sockets = 1
    cores   = var.infra_cores
    type    = "host"
  }
  scsihw      = "virtio-scsi-pci"
  bootdisk    = "scsi0"

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.storage_name
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size     = "50G"
          storage  = var.storage_name
          iothread = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }

  ipconfig0 = var.ip_mode == "dhcp" ? "ip=dhcp" : "ip=${var.infra3_ip}/${var.netmask},gw=${var.gateway}"

  ciuser     = var.ssh_user
  cipassword = var.ssh_password
  sshkeys    = var.ssh_public_key
}
