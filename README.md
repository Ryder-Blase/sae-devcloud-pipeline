# SAE6.devcloud.01 - Infrastructure CI/CD sur Proxmox

## Déploiement

```bash
./deploy.sh
```

Le script configure de manière interactive toute l'infrastructure.

---

## Infrastructure déployée

- 1 VM GitLab (code + CI/CD + Docker Registry)
- 3 VMs Kubernetes (1 master + 2 workers)
- Application Python déployée
- Template Debian créé
- Configuration réseau et SSH

## Caractéristiques

- Script unique pour tout le déploiement
- Configuration interactive
- Calcul automatique des ressources
- Compatible avec tout Proxmox VE
- Durée : 45-60 minutes

## Architecture

```
Proxmox
    ├─► VM GitLab (IP: x.x.x.41)
    │   - GitLab CE
    │   - Docker Registry
    │   - CI/CD Runner
    │
    ├─► VM K8s Master (IP: x.x.x.42)
    │   - Control Plane
    │   - kubectl, kubeadm
    │
    ├─► VM K8s Worker 1 (IP: x.x.x.43)
    │   - Pods applicatifs
    │
    └─► VM K8s Worker 2 (IP: x.x.x.44)
        - Pods applicatifs
```

---

## Prérequis

### Installation des outils

```bash
# Arch Linux
sudo pacman -S terraform ansible openssh sshpass

# Debian/Ubuntu
sudo apt install terraform ansible openssh-client sshpass

# macOS
brew install terraform ansible
```

### Proxmox VE

- Proxmox VE 7.x ou 8.x
- Accès root SSH
- Minimum 12 GB RAM (recommandé : 16 GB+)
- Minimum 6 CPU (recommandé : 8+)
- 300 GB d'espace disque
- 4 IPs libres sur le réseau

---

## Utilisation

### Lancement

```bash
./deploy.sh
```

### Configuration

Le script demande :

1. Configuration Proxmox
   - IP du serveur
   - Utilisateur (root)
   - Mot de passe
   - Nom du nœud (pve)
   - Storage (local-lvm)

2. Ressources
   - Nombre de CPU
   - RAM en GB
   (Répartition automatique)

3. Réseau
   - Gateway
   - IPs des 4 VMs

4. SSH
   - Utilisateur des VMs (debian)
   - Mot de passe (debian123)

5. Confirmation

### Exemple

```bash
$ ./deploy.sh

Adresse IP Proxmox [192.168.122.227]: <ENTER>
Utilisateur [root]: <ENTER>
Mot de passe: ********
Nombre de CPU [6]: <ENTER>
RAM en GB [16]: <ENTER>

Ressources allouées :
  GitLab    : 2 CPU, 4 GB RAM
  K8s Master: 1 CPU, 3 GB RAM
  K8s Workers (x2): 1 CPU, 3 GB RAM

Gateway [192.168.122.1]: <ENTER>
IP GitLab [192.168.122.41]: <ENTER>
IP K8s Master [192.168.122.42]: <ENTER>
IP K8s Worker 1 [192.168.122.43]: <ENTER>
IP K8s Worker 2 [192.168.122.44]: <ENTER>

[Déploiement - 45-60 minutes]
[OK] Proxmox configuré
[OK] Template Debian créé
[OK] VMs créées
[OK] GitLab installé
[OK] Kubernetes configuré
[OK] Application déployée

🎉 Terminé !
```

---

## 📊 Allocation des ressources

Le script calcule automatiquement selon votre serveur :

| Serveur | GitLab | K8s Master | K8s Workers (x2) | Total |
|---------|--------|------------|------------------|-------|
| 6 CPU / 16 GB | 2C / 4G | 1C / 3G | 1C / 3G | 5C / 13G |
| 8 CPU / 32 GB | 2C / 8G | 2C / 6G | 2C / 6G | 8C / 26G |
| 12 CPU / 64 GB | 4C / 12G | 2C / 8G | 2C / 8G | 10C / 36G |

Le script utilise **max 70% des ressources** pour laisser de la marge au host.

---

## 🌐 Adaptation réseau automatique

**Exemple 1 - Réseau 192.168.122.0/24**
```
Proxmox : 192.168.122.227
→ Suggère : 192.168.122.41-44
```

**Exemple 2 - Réseau 10.0.0.0/24**
```
Proxmox : 10.0.0.50
→ Suggère : 10.0.0.41-44
```

**Exemple 3 - Réseau 172.16.0.0/24**
```
Proxmox : 172.16.0.100
→ Suggère : 172.16.0.41-44
```

Le script détecte automatiquement et vous pouvez modifier les suggestions !

---

## 📡 Après le déploiement

Les informations sont sauvées dans `deployment-info.txt`.

### URLs

```
GitLab      : http://<ip_gitlab>
Registry    : http://<ip_gitlab>:5050
Application : http://<ip_master>:30080
```

### Mot de passe GitLab

```bash
ssh debian@<ip_gitlab> 'sudo cat /etc/gitlab/initial_root_password'
```

### Commandes utiles

```bash
# Vérifier Kubernetes
ssh debian@<ip_master> 'kubectl get nodes'
ssh debian@<ip_master> 'kubectl get pods -A'

# Vérifier GitLab
ssh debian@<ip_gitlab> 'sudo gitlab-ctl status'

# Tester l'application
curl http://<ip_master>:30080/health
```

---

## Dépannage

### SSH vers Proxmox

```bash
ssh-copy-id root@<ip_proxmox>
```

### Vérifier les VMs

```bash
# Sur Proxmox
ssh root@<ip_proxmox> 'qm list'
ssh root@<ip_proxmox> 'qm status <vmid>'
```

### GitLab ne démarre pas

GitLab nécessite **minimum 3 GB de RAM**. Vérifiez :

```bash
ssh debian@<ip_gitlab> 'free -h'
ssh debian@<ip_gitlab> 'sudo gitlab-ctl status'
```

### Recommencer le déploiement

```bash
# Détruire tout
cd terraform
terraform destroy -auto-approve
cd ..

# Relancer
./deploy.sh
```

---

## Structure du projet

```
sae-albert-fin/
├── deploy.sh           # Script principal
├── README.md
├── .gitignore
├── ansible/            # Configuration Ansible
│   ├── ansible.cfg
│   ├── inventory.ini   (généré)
│   ├── site.yml
│   └── playbooks/
│       ├── 00-init.yml
│       ├── 01-gitlab.yml
│       ├── 02-kubernetes.yml
│       └── 03-deploy-app.yml
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars  (généré)
└── python/             # Application
    ├── Dockerfile
    ├── requirements.txt
    ├── run.py
    └── addrservice/
```

---

## Temps de déploiement

- Configuration interactive : 2-3 minutes
- Setup Proxmox + Template : 5-10 minutes
- Création des VMs : 3-5 minutes
- Configuration GitLab : 15-20 minutes
- Configuration Kubernetes : 10-15 minutes
- Déploiement application : 2-3 minutes

Total : 45-60 minutes

---

## Pour la SAE

### Livrables

1. **Vidéo démo (5 min max)**
   - Lancer `./deploy.sh`
   - Montrer le récapitulatif
   - Accéder aux services déployés

2. **Rapport technique**
   - Architecture réseau (voir ci-dessus)
   - Choix techniques (GitLab, K8s, Terraform, Ansible)

3. **Bilan de compétences**
   - Infrastructure as Code (Terraform)
   - Configuration Management (Ansible)
   - Orchestration (Kubernetes)
   - CI/CD (GitLab)
   - Virtualisation (Proxmox)

---

## Licence

Projet SAE6.devcloud.01

---

## Ressources

- [Documentation Proxmox](https://pve.proxmox.com/wiki/Main_Page)
- [Documentation GitLab](https://docs.gitlab.com/)
- [Documentation Kubernetes](https://kubernetes.io/docs/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
