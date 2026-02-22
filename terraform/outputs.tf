output "gitlab_vm_ip" {
  description = "Adresse IP de la VM GitLab"
  value       = var.ip_mode == "dhcp" ? proxmox_vm_qemu.gitlab.default_ipv4_address : var.gitlab_ip
}

output "infra1_vm_ip" {
  description = "Adresse IP de la VM Infrastructure 1"
  value       = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra1.default_ipv4_address : var.infra1_ip
}

output "infra2_vm_ip" {
  description = "Adresse IP de la VM Infrastructure 2"
  value       = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra2.default_ipv4_address : var.infra2_ip
}

output "infra3_vm_ip" {
  description = "Adresse IP de la VM Infrastructure 3"
  value       = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra3.default_ipv4_address : var.infra3_ip
}

output "all_vms" {
  description = "Liste de toutes les VMs créées"
  value = {
    gitlab = {
      name = proxmox_vm_qemu.gitlab.name
      ip   = var.ip_mode == "dhcp" ? proxmox_vm_qemu.gitlab.default_ipv4_address : var.gitlab_ip
    }
    infra1 = {
      name = proxmox_vm_qemu.infra1.name
      ip   = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra1.default_ipv4_address : var.infra1_ip
    }
    infra2 = {
      name = proxmox_vm_qemu.infra2.name
      ip   = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra2.default_ipv4_address : var.infra2_ip
    }
    infra3 = {
      name = proxmox_vm_qemu.infra3.name
      ip   = var.ip_mode == "dhcp" ? proxmox_vm_qemu.infra3.default_ipv4_address : var.infra3_ip
    }
  }
}
