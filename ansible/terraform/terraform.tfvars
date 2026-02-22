# Configuration générée automatiquement le dim. 22 févr. 2026 20:25:00 CET

proxmox_api_url      = "https://10.129.4.31:8006/api2/json"
proxmox_user         = "root@pam"
proxmox_password     = "rootroot"
proxmox_tls_insecure = true

proxmox_node   = "pve"
template_name  = "ubuntu-template"
storage_name   = "local-lvm"

ip_mode = "static"
netmask = "24"

ssh_user     = "debian"
ssh_password = "debian123"
ssh_public_key = <<-EOT
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKx/epnkaL+kVbiTdpsVluDkc/9cM0A69RmeEYPu4Z8EVgnbTQYSHgwx3xPUAJ9DZfI6Pk4X5TcVNRztOup+As8/qKxpw5uFqtw27VF4ApsQvNUpV2UqP/zQWtpvZj4x2uyNmnjb/PrPF4Nxg+BwEXV2au5FnYnYLmflKw7Lb6bDAKIzFz0ZZIrBTH2/aG2thK2s7D0LH9urLncICmk6H6dtRlyYfKVRW2fsAzDODDt3rW77lKMHIAb4XXQ14TUu1/b2azIKKAuHecLbrcIXYXb7+k0nXejdvhqKXyuyVqohm7m+ngrnl17uQ4tm0wIla7st8LgZoaaJD/QM2ueXegKRBJGYoqL8lVIgopTo/AqtVENschUaNQ9d1NueSogcpJ5nK98w0ahoJhuVgDjTnlb3ORrlWrXNbxw8obzWdy87CKNTutgRoxh3MuiN5VaEJrjCBK8uQXOvafctu6OKmc6qq/hW4ZRk5IsRx62GS2Oh7oMyvKB+KSDjYxWVY6TIhPXGPqbzBMwknbqI6ibE8Lm1X9IM9TEfg1vx7UcHRCl7TogyRhwlyA8DY8inJSJrYaGAZaD4ji+t3vCq4RvdAan1pRjPu+U9R04CWJhE1fcJHmH1ZUGwioYLXatzO5Mgmdff3ZqKtC9uCZATWf9UaOM6l+proNOh3yK8ksybswOw== linux@archlinux
EOT

gitlab_ip  = "10.129.4.42"
infra1_ip  = "10.129.4.43"
infra2_ip  = "10.129.4.44"
infra3_ip  = "10.129.4.45"
gateway    = "10.129.4.1"

# Ressources des VMs
gitlab_cores  = 4
gitlab_memory = 10240
infra_cores   = 4
infra_memory  = 8192
