variable "proxmox_api_url" {
  description = "URL de l'API Proxmox"
  type        = string
}

variable "proxmox_user" {
  description = "Utilisateur Proxmox (ex: root@pam)"
  type        = string
}

variable "proxmox_password" {
  description = "Mot de passe Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Désactiver la vérification TLS"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Nom du noeud Proxmox"
  type        = string
  default     = "pve"
}

variable "template_name" {
  description = "Nom du template Debian"
  type        = string
  default     = "ubuntu-template"
}

variable "storage_name" {
  description = "Nom du storage Proxmox"
  type        = string
  default     = "local-lvm"
}

variable "ssh_user" {
  description = "Utilisateur SSH"
  type        = string
  default     = "ubuntu"
}

variable "ssh_password" {
  description = "Mot de passe SSH"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Clé publique SSH"
  type        = string
}

variable "gitlab_ip" {
  description = "Adresse IP pour GitLab VM"
  type        = string
  default     = "10.129.4.41"
}

variable "infra1_ip" {
  description = "Adresse IP pour Infrastructure VM 1"
  type        = string
  default     = "10.129.4.42"
}

variable "infra2_ip" {
  description = "Adresse IP pour Infrastructure VM 2"
  type        = string
  default     = "10.129.4.43"
}

variable "infra3_ip" {
  description = "Adresse IP pour Infrastructure VM 3"
  type        = string
  default     = "10.129.4.44"
}

variable "gateway" {
  description = "Passerelle réseau"
  type        = string
  default     = "10.129.4.1"
}

variable "gitlab_cores" {
  description = "Nombre de CPU pour GitLab VM"
  type        = number
  default     = 2
}

variable "gitlab_memory" {
  description = "RAM pour GitLab VM en MB"
  type        = number
  default     = 8192
}

variable "infra_cores" {
  description = "Nombre de CPU pour les VMs K8s"
  type        = number
  default     = 1
}

variable "infra_memory" {
  description = "RAM pour les VMs K8s en MB"
  type        = number
  default     = 4096
}
