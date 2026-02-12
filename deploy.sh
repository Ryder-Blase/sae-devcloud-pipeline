#!/bin/bash

# Script de déploiement SAE6.devcloud.01
# Déploie GitLab, Kubernetes et l'application sur Proxmox

set -e
set -o pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Fonctions utilitaires
print_success() { echo -e "${GREEN}[OK] $1${NC}"; }
print_error() { echo -e "${RED}[ERREUR] $1${NC}"; }
print_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
print_title() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
}
print_section() { echo -e "\n${CYAN}▸ $1${NC}"; }

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/sae-deploy-$$"

# ============================================================================
# ÉTAPE 1 : COLLECTE DES INFORMATIONS
# ============================================================================

collect_configuration() {
    clear
    print_title "Configuration du déploiement SAE6.devcloud.01"
    
    echo "Déploiement :"
    echo "  - 1 VM GitLab (code + registry)"
    echo "  - 3 VMs Kubernetes (1 master + 2 workers)"
    echo ""
    read -p "Appuyez sur ENTRÉE pour continuer..."
    
    # ===== Configuration Proxmox =====
    print_section "1/6 Configuration Proxmox"
    echo ""
    
    read -p "Adresse IP de votre serveur Proxmox [10.129.4.31]: " PROXMOX_HOST
    PROXMOX_HOST=${PROXMOX_HOST:-10.129.4.31}
    
    read -p "Utilisateur Proxmox [root]: " PROXMOX_USER
    PROXMOX_USER=${PROXMOX_USER:-root}
    
    read -sp "Mot de passe Proxmox [rootroot]: " PROXMOX_PASSWORD
    PROXMOX_PASSWORD=${PROXMOX_PASSWORD:-rootroot}
    echo ""
    
    read -p "Nom du nœud Proxmox [pve]: " PROXMOX_NODE
    PROXMOX_NODE=${PROXMOX_NODE:-pve}
    
    read -p "Nom du storage [local-lvm]: " STORAGE_NAME
    STORAGE_NAME=${STORAGE_NAME:-local-lvm}
    
    print_success "Configuration Proxmox enregistrée"
    
    # ===== Détection des ressources Proxmox =====
    print_section "2/6 Détection des ressources du serveur"
    echo ""
    
    read -p "Nombre de CPU/threads disponibles [4]: " TOTAL_CPU
    TOTAL_CPU=${TOTAL_CPU:-4}
    
    read -p "RAM disponible en GB [32]: " TOTAL_RAM_GB
    TOTAL_RAM_GB=${TOTAL_RAM_GB:-32}
    
    # Calcul automatique des ressources optimales
    TOTAL_RAM=$((TOTAL_RAM_GB * 1024))
    
    # Allocation des ressources (70% max)
    AVAILABLE_CPU=$((TOTAL_CPU * 7 / 10))
    AVAILABLE_RAM=$((TOTAL_RAM * 7 / 10))
    
    # Distribution
    read -p "Nombre de vCPUs par VM (GitLab & K8s) [4]: " VM_CORES
    VM_CORES=${VM_CORES:-4}
    GITLAB_CORES=$VM_CORES
    INFRA_CORES=$VM_CORES

    GITLAB_MEMORY=10240
    INFRA_MEMORY=8192

    echo ""
    echo "Ressources allouées :"
    echo "  Toutes les VMs : ${VM_CORES} CPU"
    echo "  RAM GitLab     : $((GITLAB_MEMORY / 1024)) GB"
    echo "  RAM K8s Nodes  : $((INFRA_MEMORY / 1024)) GB"
    echo ""
    read -p "Confirmer les ressources ? (Y/n): " confirm_resources
    if [[ "$confirm_resources" =~ ^[Nn]$ ]]; then
        read -p "Nombre de vCPUs [${VM_CORES}]: " custom_cpu
        VM_CORES=${custom_cpu:-$VM_CORES}
        GITLAB_CORES=$VM_CORES
        INFRA_CORES=$VM_CORES
        read -p "GitLab - RAM en MB [${GITLAB_MEMORY}]: " custom_gitlab_ram
        GITLAB_MEMORY=${custom_gitlab_ram:-$GITLAB_MEMORY}
        read -p "K8s Nodes - RAM en MB [${INFRA_MEMORY}]: " custom_infra_ram
        INFRA_MEMORY=${custom_infra_ram:-$INFRA_MEMORY}
    fi
    
    print_success "Ressources configurées"
    
    # ===== Configuration réseau =====
    print_section "3/6 Configuration réseau"
    echo "Choisissez le mode d'adressage IP :"
    echo "  1) Statique (recommandé pour Kubernetes)"
    echo "  2) DHCP (Dynamique)"
    read -p "Sélection [1]: " IP_MODE_SEL
    IP_MODE_SEL=${IP_MODE_SEL:-1}

    if [ "$IP_MODE_SEL" = "2" ]; then
        IP_MODE="dhcp"
        print_info "Mode DHCP sélectionné. Les IPs seront récupérées dynamiquement via Proxmox Agent."
        IP_GITLAB="dhcp"
        IP_INFRA1="dhcp"
        IP_INFRA2="dhcp"
        IP_INFRA3="dhcp"
        GATEWAY=""
        NETMASK="24"
    else
        IP_MODE="static"
        # Détecter le réseau depuis l'IP Proxmox
        NETWORK_PREFIX=$(echo $PROXMOX_HOST | cut -d. -f1-3)
        read -p "Passerelle réseau [${NETWORK_PREFIX}.1]: " GATEWAY
        GATEWAY=${GATEWAY:-${NETWORK_PREFIX}.1}
        read -p "Masque réseau CIDR [24]: " NETMASK
        NETMASK=${NETMASK:-24}
        echo ""
        echo "IPs des VMs (suggérées sur le réseau ${NETWORK_PREFIX}.0/${NETMASK}) :"
        read -p "  IP GitLab VM [${NETWORK_PREFIX}.42]: " IP_GITLAB
        IP_GITLAB=${IP_GITLAB:-${NETWORK_PREFIX}.42}
        read -p "  IP K8s Master [${NETWORK_PREFIX}.43]: " IP_INFRA1
        IP_INFRA1=${IP_INFRA1:-${NETWORK_PREFIX}.43}
        read -p "  IP K8s Worker 1 [${NETWORK_PREFIX}.44]: " IP_INFRA2
        IP_INFRA2=${IP_INFRA2:-${NETWORK_PREFIX}.44}
        read -p "  IP K8s Worker 2 [${NETWORK_PREFIX}.45]: " IP_INFRA3
        IP_INFRA3=${IP_INFRA3:-${NETWORK_PREFIX}.45}
    fi
    
    print_success "Configuration réseau ($IP_MODE) enregistrée"
    
    # ===== Configuration SSH =====
    print_section "4/6 Configuration SSH des VMs"
    echo ""
    
    read -p "Utilisateur SSH des VMs [debian]: " SSH_USER
    SSH_USER=${SSH_USER:-debian}
    
    read -sp "Mot de passe SSH des VMs [debian123]: " SSH_PASSWORD
    SSH_PASSWORD=${SSH_PASSWORD:-debian123}
    echo ""
    
    SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
    if [ ! -f "$SSH_KEY_PATH" ]; then
        print_info "Clé SSH non trouvée"
        read -p "Créer une nouvelle clé SSH ? (Y/n): " create_key
        if [[ ! "$create_key" =~ ^[Nn]$ ]]; then
            ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
            print_success "Clé SSH créée"
        else
            print_error "Une clé SSH est requise"
            exit 1
        fi
    fi
    
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH")
    print_success "Clé SSH chargée"
    
    # ===== Configuration du template =====
    print_section "5/6 Configuration du template Debian"
    echo ""
    
    read -p "ID du template à créer [9000]: " TEMPLATE_ID
    TEMPLATE_ID=${TEMPLATE_ID:-9000}
    
    read -p "Nom du template [ubuntu-template]: " TEMPLATE_NAME
    TEMPLATE_NAME=${TEMPLATE_NAME:-ubuntu-template}
    
    print_success "Template configuré"
    
    # ===== Récapitulatif =====
    print_section "6/6 Récapitulatif de la configuration"
    echo ""
    echo -e "${MAGENTA}┌─ Serveur Proxmox${NC}"
    echo "│  IP          : $PROXMOX_HOST"
    echo "│  Utilisateur : $PROXMOX_USER"
    echo "│  Node        : $PROXMOX_NODE"
    echo "│  Storage     : $STORAGE_NAME"
    echo ""
    echo -e "${MAGENTA}┌─ Réseau${NC}"
    echo "│  Gateway     : $GATEWAY/$NETMASK"
    echo "│  GitLab      : $IP_GITLAB"
    echo "│  K8s Master  : $IP_INFRA1"
    echo "│  K8s Worker1 : $IP_INFRA2"
    echo "│  K8s Worker2 : $IP_INFRA3"
    echo ""
    echo -e "${MAGENTA}┌─ Ressources${NC}"
    echo "│  GitLab      : ${GITLAB_CORES} CPU, $((GITLAB_MEMORY / 1024)) GB RAM"
    echo "│  K8s Nodes   : ${INFRA_CORES} CPU, $((INFRA_MEMORY / 1024)) GB RAM (x3)"
    echo ""
    echo -e "${MAGENTA}┌─ Template${NC}"
    echo "│  ID          : $TEMPLATE_ID"
    echo "│  Nom         : $TEMPLATE_NAME"
    echo ""
    
    read -p "Confirmer et lancer le déploiement ? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_error "Déploiement annulé"
        exit 0
    fi
    
    print_success "Configuration validée - Début du déploiement"
}

# ============================================================================
# ÉTAPE 2 : VÉRIFICATION DES PRÉREQUIS
# ============================================================================

check_prerequisites() {
    print_title "Vérification des prérequis"
    
    local missing=0
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform n'est pas installé"
        missing=1
    else
        print_success "Terraform installé"
    fi
    
    # Ansible
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible n'est pas installé"
        missing=1
    else
        print_success "Ansible installé"
    fi
    
    # SSH et sshpass
    if ! command -v ssh &> /dev/null; then
        print_error "SSH n'est pas installé"
        missing=1
    else
        print_success "SSH installé"
    fi
    
    if ! command -v sshpass &> /dev/null; then
        print_info "Installation de sshpass recommandée pour l'authentification SSH"
        # Pas bloquant, on peut utiliser les clés SSH
    else
        print_success "sshpass installé"
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        print_error "Installez les outils manquants et relancez le script"
        exit 1
    fi
    
    echo ""
    print_success "Tous les prérequis sont satisfaits"
}

# ============================================================================
# ÉTAPE 3 : TEST DE CONNEXION PROXMOX
# ============================================================================

test_proxmox_connection() {
    print_title "Test de connexion à Proxmox"
    
    print_info "Tentative de connexion à $PROXMOX_USER@$PROXMOX_HOST..."
    
    # Test avec sshpass si disponible
    if command -v sshpass &> /dev/null; then
        if sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$PROXMOX_USER@$PROXMOX_HOST" "echo 'OK'" &> /dev/null; then
            print_success "Connexion SSH réussie (avec mot de passe)"
            USE_SSHPASS=true
            return 0
        fi
    fi
    
    # Test avec clé SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "$PROXMOX_USER@$PROXMOX_HOST" "echo 'OK'" &> /dev/null; then
        print_success "Connexion SSH réussie (avec clé)"
        USE_SSHPASS=false
        return 0
    fi
    
    # Échec - proposer de copier la clé
    print_error "Impossible de se connecter à Proxmox"
    echo ""
    echo "Solutions possibles :"
    echo "  1. Copier votre clé SSH sur Proxmox"
    echo "  2. Installer sshpass pour utiliser le mot de passe"
    echo ""
    read -p "Voulez-vous copier votre clé SSH maintenant ? (Y/n): " copy_key
    
    if [[ ! "$copy_key" =~ ^[Nn]$ ]]; then
        if command -v sshpass &> /dev/null; then
            sshpass -p "$PROXMOX_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST"
        else
            ssh-copy-id -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST"
        fi
        print_success "Clé SSH copiée"
        USE_SSHPASS=false
    else
        print_error "Impossible de continuer sans connexion SSH"
        exit 1
    fi
}

# Fonction pour exécuter des commandes SSH
ssh_exec() {
    if [ "$USE_SSHPASS" = true ] && command -v sshpass &> /dev/null; then
        sshpass -p "$PROXMOX_PASSWORD" ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "$@"
    else
        ssh -o StrictHostKeyChecking=no "$PROXMOX_USER@$PROXMOX_HOST" "$@"
    fi
}

scp_file() {
    local src="$1"
    local dst="$2"
    if [ "$USE_SSHPASS" = true ] && command -v sshpass &> /dev/null; then
        sshpass -p "$PROXMOX_PASSWORD" scp -o StrictHostKeyChecking=no "$src" "$PROXMOX_USER@$PROXMOX_HOST:$dst"
    else
        scp -o StrictHostKeyChecking=no "$src" "$PROXMOX_USER@$PROXMOX_HOST:$dst"
    fi
}

# ============================================================================
# ÉTAPE 4 : CONFIGURATION PROXMOX ET CRÉATION DU TEMPLATE
# ============================================================================

setup_proxmox_and_template() {
    print_title "Configuration de Proxmox et création du template"
    
    print_info "Création du script de configuration sur Proxmox..."
    
    # Créer le script de setup directement sur Proxmox
    cat > /tmp/setup-proxmox-temp.sh <<'EOFSCRIPT'
#!/bin/bash
set -e

TEMPLATE_ID="__TEMPLATE_ID__"
TEMPLATE_NAME="__TEMPLATE_NAME__"
STORAGE="__STORAGE__"

echo "=== Configuration Proxmox ==="

# 1. Optimisations système
echo "Optimisations sysctl..."
cat <<EOF_SYSCTL | tee /etc/sysctl.d/99-sae-optimization.conf
vm.swappiness = 10
fs.file-max = 524288
net.core.somaxconn = 1024
EOF_SYSCTL
sysctl -p /etc/sysctl.d/99-sae-optimization.conf

# 2. Créer le token API
echo "Création du token API..."
pveum user token add root@pam terraform --privsep 0 2>/dev/null || echo "Token déjà existant"

# 2. Télécharger l'image Ubuntu si nécessaire
cd /var/lib/vz/template/iso
if [ ! -f "ubuntu-22.04-cloudimg.img" ]; then
    echo "Téléchargement de Ubuntu 22.04 Cloud..."
    wget -q --show-progress -O ubuntu-22.04-cloudimg.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
    echo "Image téléchargée"
else
    echo "Image Ubuntu déjà présente"
fi

# 3. Supprimer l'ancien template si existe
if qm status $TEMPLATE_ID &>/dev/null; then
    echo "Nettoyage de l'ancien template/VM $TEMPLATE_ID..."
    qm unlock $TEMPLATE_ID 2>/dev/null || true
    qm destroy $TEMPLATE_ID
fi

# 4. Créer la VM template
echo "Création du template VM..."
qm create $TEMPLATE_ID --name $TEMPLATE_NAME --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# 5. Importer et Configurer le disque (Méthode Robuste)
echo "Import et configuration du disque (Cloud-Image)..."
qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --boot c --bootdisk scsi0
# Utilisation de import-from pour éviter les erreurs de noms de disque (disk-0 vs disk-1)
qm set $TEMPLATE_ID --scsi0 ${STORAGE}:0,import-from=/var/lib/vz/template/iso/ubuntu-22.04-cloudimg.img

# 6. Configuration Cloud-Init
echo "Configuration Cloud-Init..."
qm set $TEMPLATE_ID --ide2 ${STORAGE}:cloudinit
qm set $TEMPLATE_ID --serial0 socket --vga serial0
qm set $TEMPLATE_ID --agent enabled=1

# 7. Conversion en template
echo "Conversion en template..."
qm template $TEMPLATE_ID
# Vérifier si c'est bien un template
if ! qm config $TEMPLATE_ID | grep -q "template: 1"; then
    echo "ERREUR: Échec de la conversion en template"
    exit 1
fi


# 9. Afficher le token (pour info)
echo ""
echo "Token API : root@pam!terraform"
pveum user token list root@pam 2>/dev/null || true

EOFSCRIPT
    
    # Remplacer les variables
    sed -i "s/__TEMPLATE_ID__/$TEMPLATE_ID/g" /tmp/setup-proxmox-temp.sh
    sed -i "s/__TEMPLATE_NAME__/$TEMPLATE_NAME/g" /tmp/setup-proxmox-temp.sh
    sed -i "s/__STORAGE__/$STORAGE_NAME/g" /tmp/setup-proxmox-temp.sh
    
    # Copier et exécuter sur Proxmox
    print_info "Copie du script sur Proxmox..."
    scp_file /tmp/setup-proxmox-temp.sh /tmp/setup-proxmox.sh
    
    print_info "Exécution du script de configuration (peut prendre 5-10 minutes)..."
    ssh_exec "bash -e /tmp/setup-proxmox.sh" 2>&1 | tee /tmp/proxmox-setup.log
    
    # Vérifier l'état de sortie du script Proxmox
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        print_error "Le script Proxmox a échoué"
        exit 1
    fi
    
    # Récupérer le token secret
    print_info "Récupération du token API..."
    TOKEN_INFO=$(ssh_exec "pveum user token list root@pam" 2>/dev/null || echo "")
    
    # Le token secret n'est affiché qu'à la création, on va le générer nous-même
    PROXMOX_TOKEN_ID="root@pam!terraform"
    PROXMOX_TOKEN_SECRET=$(openssl rand -hex 32)  # Génération aléatoire pour la suite
    
    # Note: En réalité, il faudrait utiliser le vrai token, mais pour simplifier on utilisera
    # l'authentification par mot de passe pour Terraform via un provider alternatif si besoin
    
    print_success "Configuration Proxmox terminée"
    
    rm -f /tmp/setup-proxmox-temp.sh
}

# ============================================================================
# ÉTAPE 5 : GÉNÉRATION DE LA CONFIGURATION TERRAFORM
# ============================================================================

generate_terraform_config() {
    print_title "Génération de la configuration Terraform"
    
    mkdir -p "$SCRIPT_DIR/terraform"
    
    # Créer terraform.tfvars
    print_info "Création de terraform.tfvars..."
    cat > "$SCRIPT_DIR/terraform/terraform.tfvars" <<EOF
# Configuration générée automatiquement le $(date)

proxmox_api_url      = "https://${PROXMOX_HOST}:8006/api2/json"
proxmox_user         = "${PROXMOX_USER}@pam"
proxmox_password     = "${PROXMOX_PASSWORD}"
proxmox_tls_insecure = true

proxmox_node   = "${PROXMOX_NODE}"
template_name  = "${TEMPLATE_NAME}"
storage_name   = "${STORAGE_NAME}"

ip_mode = "${IP_MODE}"
netmask = "${NETMASK}"

ssh_user     = "${SSH_USER}"
ssh_password = "${SSH_PASSWORD}"
ssh_public_key = <<-EOT
${SSH_PUBLIC_KEY}
EOT

gitlab_ip  = "${IP_GITLAB}"
infra1_ip  = "${IP_INFRA1}"
infra2_ip  = "${IP_INFRA2}"
infra3_ip  = "${IP_INFRA3}"
gateway    = "${GATEWAY}"

# Ressources des VMs
gitlab_cores  = ${GITLAB_CORES}
gitlab_memory = ${GITLAB_MEMORY}
infra_cores   = ${INFRA_CORES}
infra_memory  = ${INFRA_MEMORY}
EOF
    
    # Mettre à jour variables.tf pour inclure les nouvelles variables de ressources
    if ! grep -q "gitlab_cores" "$SCRIPT_DIR/terraform/variables.tf" 2>/dev/null; then
        print_info "Ajout des variables de ressources dans variables.tf..."
        cat >> "$SCRIPT_DIR/terraform/variables.tf" <<EOF

variable "proxmox_user" {
  description = "Utilisateur Proxmox (alternative au token)"
  type        = string
  default     = ""
}

variable "proxmox_password" {
  description = "Mot de passe Proxmox (alternative au token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_cores" {
  description = "Nombre de CPU pour GitLab"
  type        = number
  default     = 2
}

variable "gitlab_memory" {
  description = "RAM pour GitLab en MB"
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
EOF
    fi
    
    # Mettre à jour main.tf pour utiliser les variables de ressources et optimisations
    print_info "Mise à jour de main.tf avec les ressources et optimisations..."
    sed -i 's/agent       = 0/agent       = 1/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    sed -i 's/cores       = 1/cores       = var.gitlab_cores/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    sed -i 's/memory      = 8192/memory      = var.gitlab_memory/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    sed -i 's/cores       = 1/cores       = var.infra_cores/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    sed -i 's/memory      = 4096/memory      = var.infra_memory/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    
    # Ajouter ballooning et CPU type host si pas présent
    grep -q "balloon" "$SCRIPT_DIR/terraform/main.tf" || {
        sed -i '/memory      = var.gitlab_memory/a \  balloon     = 2048' "$SCRIPT_DIR/terraform/main.tf"
        sed -i '/memory      = var.infra_memory/a \  balloon     = 1024' "$SCRIPT_DIR/terraform/main.tf"
    }
    grep -q "type    = \"host\"" "$SCRIPT_DIR/terraform/main.tf" || {
        sed -i '/cores   = var.*_cores/a \    type    = "host"' "$SCRIPT_DIR/terraform/main.tf"
    }
    
    # Correction d'un bug potentiel sur les virgules dans ipconfig0 (uniquement en statique)
    if [ "$IP_MODE" = "static" ]; then
        sed -i 's/ip=${var.gitlab_ip},/ip=${var.gitlab_ip}\/24,/g' "$SCRIPT_DIR/terraform/main.tf" 2>/dev/null || true
    fi
    
    print_success "Configuration Terraform générée"
}

# ============================================================================
# ÉTAPE 6 : DÉPLOIEMENT DE L'INFRASTRUCTURE AVEC TERRAFORM
# ============================================================================

deploy_infrastructure() {
    print_title "Déploiement de l'infrastructure avec Terraform"
    
    cd "$SCRIPT_DIR/terraform"
    
    print_info "Initialisation de Terraform..."
    terraform init -upgrade
    
    print_info "Validation de la configuration..."
    terraform validate
    
    print_info "Déploiement des VMs (3-5 minutes)..."
    terraform apply -auto-approve
    
    print_success "Infrastructure déployée"
    
    cd "$SCRIPT_DIR"
}

# ============================================================================
# ÉTAPE 6bis : DÉCOUVERTE DES IPS (PROVISIONNEMENT DYNAMIQUE)
# ============================================================================

discover_ips() {
    print_title "Découverte des adresses IP"
    cd "$SCRIPT_DIR/terraform"
    
    if [ "$IP_MODE" = "dhcp" ]; then
        print_info "Attente des adresses DHCP (Proxmox Agent)..."
        local max_attempts=18
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            print_info "Tentative de récupération $attempt/$max_attempts..."
            terraform refresh &>/dev/null
            
            # Vérifier si l'IP de GitLab est remontée (le pivot)
            LT_GITLAB=$(terraform output -raw gitlab_vm_ip 2>/dev/null || echo "")
            IP_GITLAB=$(echo $LT_GITLAB | tr -d '"' | tr -d '\r')
            
            if [[ -n "$IP_GITLAB" && "$IP_GITLAB" != "dhcp" && "$IP_GITLAB" != "" ]]; then
                print_success "Adresses IP détectées via l'agent QEMU !"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                print_error "Délai d'attente dépassé (3 minutes). L'agent Proxmox ne répond pas."
                exit 1
            fi
            
            sleep 10
            attempt=$((attempt + 1))
        done
    fi

    # Récupération finale de toutes les IPs
    LT_GITLAB=$(terraform output -raw gitlab_vm_ip 2>/dev/null || echo "$IP_GITLAB")
    LT_INFRA1=$(terraform output -raw infra1_vm_ip 2>/dev/null || echo "$IP_INFRA1")
    LT_INFRA2=$(terraform output -raw infra2_vm_ip 2>/dev/null || echo "$IP_INFRA2")
    LT_INFRA3=$(terraform output -raw infra3_vm_ip 2>/dev/null || echo "$IP_INFRA3")
    
    IP_GITLAB=$(echo $LT_GITLAB | tr -d '"' | tr -d '\r')
    IP_INFRA1=$(echo $LT_INFRA1 | tr -d '"' | tr -d '\r')
    IP_INFRA2=$(echo $LT_INFRA2 | tr -d '"' | tr -d '\r')
    IP_INFRA3=$(echo $LT_INFRA3 | tr -d '"' | tr -d '\r')

    print_success "Provisionnement Dynamique OK : GitLab=$IP_GITLAB, Master=$IP_INFRA1"
    cd "$SCRIPT_DIR"
}

# ============================================================================
# ÉTAPE 7 : GÉNÉRATION DE L'INVENTAIRE ANSIBLE
# ============================================================================

generate_ansible_inventory() {
    print_title "Génération de l'inventaire Ansible"
    
    mkdir -p "$SCRIPT_DIR/ansible"
    
    cat > "$SCRIPT_DIR/ansible/inventory.ini" <<EOF
# Inventaire Ansible - Généré le $(date)

[gitlab]
gitlab-vm ansible_host=${IP_GITLAB} ansible_user=${SSH_USER} ansible_ssh_pass=${SSH_PASSWORD} ansible_ssh_private_key_file=~/.ssh/id_rsa

[k8s_master]
infra1-vm ansible_host=${IP_INFRA1} ansible_user=${SSH_USER} ansible_ssh_pass=${SSH_PASSWORD} ansible_ssh_private_key_file=~/.ssh/id_rsa

[k8s_workers]
infra2-vm ansible_host=${IP_INFRA2} ansible_user=${SSH_USER} ansible_ssh_pass=${SSH_PASSWORD} ansible_ssh_private_key_file=~/.ssh/id_rsa
infra3-vm ansible_host=${IP_INFRA3} ansible_user=${SSH_USER} ansible_ssh_pass=${SSH_PASSWORD} ansible_ssh_private_key_file=~/.ssh/id_rsa

[k8s:children]
k8s_master
k8s_workers

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# Configuration GitLab
gitlab_external_url=http://${IP_GITLAB}
gitlab_registry_external_url=http://${IP_GITLAB}:5050

# Configuration Kubernetes
kubernetes_version=1.28
pod_network_cidr=10.244.0.0/16

# Configuration Application  
app_name=addrservice
app_port=30080
app_replicas=2
EOF
    
    print_success "Inventaire Ansible généré"
}

# ============================================================================
# ÉTAPE 8 : ATTENTE DU DÉMARRAGE DES VMs
# ============================================================================

wait_for_vms() {
    print_title "Attente du démarrage des VMs"
    
    print_info "Attente de 15 secondes pour le démarrage complet..."
    sleep 15
    
    cd "$SCRIPT_DIR/ansible"
    
    print_info "Test de connectivité avec les VMs..."
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_info "Tentative $attempt/$max_attempts..."
        
        if ansible all -i inventory.ini -m ping &> /dev/null; then
            print_success "Toutes les VMs sont accessibles"
            cd "$SCRIPT_DIR"
            return 0
        fi
        
        sleep 30
        attempt=$((attempt + 1))
    done
    
    print_error "Certaines VMs ne répondent pas"
    print_info "Vérification manuelle..."
    ansible all -i inventory.ini -m ping
    
    cd "$SCRIPT_DIR"
    
    read -p "Voulez-vous continuer quand même ? (y/N): " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# ============================================================================
# ÉTAPE 9 : CONFIGURATION DES VMs AVEC ANSIBLE
# ============================================================================

configure_vms() {
    print_title "Configuration des VMs avec Ansible"
    
    cd "$SCRIPT_DIR/ansible"
    
    if [ ! -f "site.yml" ]; then
        print_error "Fichier site.yml introuvable"
        print_info "Vérifiez que les playbooks Ansible sont présents dans ansible/playbooks/"
        exit 1
    fi
    
    print_section "Étape 1/4 : Configuration initiale"
    ansible-playbook -i inventory.ini playbooks/00-init.yml
    print_success "Configuration initiale terminée"
    
    print_section "Étape 2/4 : Installation GitLab (15-20 min)"
    ansible-playbook -i inventory.ini playbooks/01-gitlab.yml
    print_success "GitLab installé"
    
    print_section "Étape 3/4 : Installation Kubernetes (10-15 min)"
    ansible-playbook -i inventory.ini playbooks/02-kubernetes.yml
    print_success "Kubernetes installé"

    print_section "Étape additionnelle : Optimisations système des VMs"
    ansible-playbook -i inventory.ini playbooks/04-optimization.yml
    print_success "VMs optimisées"
    
    # Étape 4/4 : Déploiement initial de l'application (supprimé ici, géré par le pipeline CI/CD)
    
    cd "$SCRIPT_DIR"
}

# ============================================================================
# ÉTAPE 10 : CONFIGURATION CI/CD GITLAB
# ============================================================================

setup_cicd_pipeline() {
    print_title "Configuration du pipeline CI/CD"
    
    print_section "Attente de disponibilité SSH de GitLab..."
    for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${SSH_USER}@${IP_GITLAB} "echo OK" &>/dev/null; then
            print_success "GitLab SSH est prêt"
            break
        fi
        echo -n "."
        sleep 5
        [ $i -eq 30 ] && { print_error "GitLab VM injoignable après 150s"; exit 1; }
    done

    print_section "Configuration Docker pour registry HTTP..."
    
    # Configurer Docker pour accepter le registry en HTTP (insecure)
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} <<EOSSH
# Backup de la config existante
sudo mkdir -p /etc/docker
[ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.\$(date +%s) 2>/dev/null || true

# Créer la configuration avec insecure-registries
sudo tee /etc/docker/daemon.json > /dev/null <<'DOCKEREOF'
{
  "insecure-registries": ["${IP_GITLAB}:5050", "10.129.4.41:5050", "localhost:5050"],
  "registry-mirrors": [],
  "storage-driver": "overlay2"
}
DOCKEREOF

# Redémarrer Docker
sudo systemctl daemon-reexec
sudo systemctl restart docker
sleep 3
EOSSH
    
    print_success "Docker configuré pour registry HTTP"
    
    print_section "Configuration kubectl pour gitlab-runner..."
    
    # Copier kubeconfig pour gitlab-runner
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_INFRA1}:~/.kube/config /tmp/kube_config_deploy || true
    
    if [ -f /tmp/kube_config_deploy ]; then
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            /tmp/kube_config_deploy ${SSH_USER}@${IP_GITLAB}:/tmp/kube_config
        
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            ${SSH_USER}@${IP_GITLAB} <<'EOSSH'
sudo mkdir -p /home/gitlab-runner/.kube
sudo cp /tmp/kube_config /home/gitlab-runner/.kube/config
sudo chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.kube
sudo chmod 600 /home/gitlab-runner/.kube/config
EOSSH
        print_success "kubectl configuré pour gitlab-runner"
    fi
    
    print_section "Configuration SSH entre runner et nodes K8s..."
    
    # Configurer SSH pour le runner
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} <<'EOSSH'
# Générer clé SSH pour gitlab-runner si nécessaire
sudo -u gitlab-runner bash -c '
if [ ! -f ~/.ssh/id_rsa ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa -q
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
fi
'
EOSSH
    
    # Récupérer la clé publique du runner
    RUNNER_KEY=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} "sudo su - gitlab-runner -c 'cat ~/.ssh/id_rsa.pub'")
    
    # Ajouter la clé sur tous les nodes K8s
    for NODE_IP in ${IP_INFRA1} ${IP_INFRA2} ${IP_INFRA3}; do
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            ${SSH_USER}@${NODE_IP} "echo '$RUNNER_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    done
    
    print_success "SSH configuré entre runner et nodes"
    
    print_section "Enregistrement automatique des GitLab Runners..."
    
    # Vérifier si les runners sont déjà enregistrés
    DOCKER_RUNNER_EXISTS=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} "sudo gitlab-runner list 2>/dev/null | grep -c 'docker-runner' | head -1" 2>/dev/null || echo "0")
    SHELL_RUNNER_EXISTS=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} "sudo gitlab-runner list 2>/dev/null | grep -c 'shell-runner' | head -1" 2>/dev/null || echo "0")
    
    # Convertir en nombre si contient des retours à la ligne
    DOCKER_RUNNER_EXISTS=$(echo "$DOCKER_RUNNER_EXISTS" | head -1 | tr -d '\n\r ')
    SHELL_RUNNER_EXISTS=$(echo "$SHELL_RUNNER_EXISTS" | head -1 | tr -d '\n\r ')
    
    if [ "$DOCKER_RUNNER_EXISTS" -eq "0" ] || [ "$SHELL_RUNNER_EXISTS" -eq "0" ]; then
        print_info "Récupération automatique du token et enregistrement des runners..."
        
        # Exécuter tout le script d'enregistrement directement sur la VM GitLab
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${IP_GITLAB} "bash -s" <<ENDBASH
#!/bin/bash

# Fonction pour récupérer le token avec plusieurs méthodes
get_runner_token() {
    # Méthode 1: PostgreSQL (le plus rapide)
    TOKEN=\$(sudo -u gitlab-psql /opt/gitlab/embedded/bin/psql -h /var/opt/gitlab/postgresql -d gitlabhq_production -t -c "SELECT runners_registration_token FROM application_settings WHERE runners_registration_token IS NOT NULL ORDER BY id DESC LIMIT 1;" 2>/dev/null | tr -d ' \t\n')
    
    if [ -n "\$TOKEN" ]; then
        echo "\$TOKEN"
        return 0
    fi
    
    # Méthode 2: gitlab-rails console
    TOKEN=\$(timeout 60 sudo gitlab-rails runner "puts ApplicationSetting.current.runners_registration_token" 2>/dev/null | tail -1 | tr -d ' \t\n')
    
    if [ -n "\$TOKEN" ]; then
        echo "\$TOKEN"
        return 0
    fi
    
    # Méthode 3: gitlab-rake
    TOKEN=\$(timeout 30 sudo gitlab-rake 'puts Gitlab::CurrentSettings.runners_registration_token' 2>/dev/null | grep -v '^\\\$' | tail -1 | tr -d ' \t\n')
    
    if [ -n "\$TOKEN" ]; then
        echo "\$TOKEN"
        return 0
    fi
    
    # Attendre un peu et réessayer avec PostgreSQL
    sleep 30
    TOKEN=\$(sudo -u gitlab-psql /opt/gitlab/embedded/bin/psql -h /var/opt/gitlab/postgresql -d gitlabhq_production -t -c "SELECT runners_registration_token FROM application_settings WHERE runners_registration_token IS NOT NULL ORDER BY id DESC LIMIT 1;" 2>/dev/null | tr -d ' \t\n')
    
    echo "\$TOKEN"
}

# Récupérer le token
TOKEN=\$(get_runner_token)

if [ -z "\$TOKEN" ]; then
    echo "[ERREUR] Impossible de récupérer le token après toutes les tentatives"
    exit 1
fi

echo "[INFO] Token récupéré: \${TOKEN:0:20}..."

# Enregistrer le runner Docker si manquant
if ! sudo gitlab-runner list 2>/dev/null | grep -q 'docker-runner'; then
    echo "[INFO] Enregistrement du runner Docker..."
    sudo gitlab-runner register \
        --non-interactive \
        --url 'http://${IP_GITLAB}' \
        --registration-token "\$TOKEN" \
        --executor 'docker' \
        --docker-image 'docker:latest' \
        --description 'docker-runner' \
        --tag-list 'deployment' \
        --docker-privileged \
        --docker-volumes '/var/run/docker.sock:/var/run/docker.sock' >/dev/null 2>&1
    
    if [ \$? -eq 0 ]; then
        echo "[OK] Runner Docker enregistré"
    else
        echo "[ERREUR] Échec enregistrement runner Docker"
    fi
fi

# Enregistrer le runner Shell si manquant
if ! sudo gitlab-runner list 2>/dev/null | grep -q 'shell-runner'; then
    echo "[INFO] Enregistrement du runner Shell..."
    sudo gitlab-runner register \
        --non-interactive \
        --url 'http://${IP_GITLAB}' \
        --registration-token "\$TOKEN" \
        --executor 'shell' \
        --description 'shell-runner' \
        --tag-list 'shell' >/dev/null 2>&1
    
    if [ \$? -eq 0 ]; then
        echo "[OK] Runner Shell enregistré"
    else
        echo "[ERREUR] Échec enregistrement runner Shell"
    fi
fi

# Redémarrer le service
sudo systemctl restart gitlab-runner

# Afficher les runners enregistrés
echo ""
echo "=== Runners enregistrés ==="
sudo gitlab-runner list 2>/dev/null

exit 0
ENDBASH
        
        if [ $? -eq 0 ]; then
            print_success "Runners enregistrés automatiquement"
        else
            print_error "Échec de l'enregistrement automatique des runners"
            print_info "Utilise './quick-fix-runner.sh' après le déploiement pour enregistrer manuellement"
        fi
    else
        print_success "Runners déjà enregistrés"
    fi
    
    print_section "Création du projet GitLab via API..."
    
    # Créer le projet via gitlab-rails (plus fiable que l'API avec auth basique)
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${IP_GITLAB} <<'EOSSH'
      sudo gitlab-rails runner "
        user = User.find_by_username('root')
        project = Project.find_by_full_path('root/addressbook')
        if project
          puts 'Project already exists'
        else
          params = {
            name: 'addressbook',
            path: 'addressbook',
            namespace_id: user.namespace.id,
            visibility_level: 20
          }
          project = Projects::CreateService.new(user, params).execute
          if project.persisted?
            puts 'Project created successfully'
          else
            puts 'ERROR: ' + project.errors.full_messages.join(', ')
            exit 1
          end
        end
      "
EOSSH
    
    if [ $? -eq 0 ]; then
        print_success "Projet créé"
    else
        print_error "Échec de la création du projet"
        exit 1
    fi
    
    # Génération d'un token d'accès via rails pour l'API (AVANT utilisation)
    PRIVATE_TOKEN="sae-token-$(date +%s)"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} <<EOSSH
sudo gitlab-rails runner "
user = User.find_by_username('root')
token = user.personal_access_tokens.create(scopes: ['api', 'write_repository'], name: 'SAE-Deploy-Token', expires_at: 30.days.from_now)
token.set_token('${PRIVATE_TOKEN}')
token.save!

# Récupérer le mot de passe root initial et l'injecter comme variable de projet
root_password = File.read('/etc/gitlab/initial_root_password').match(/Password: (.*)/)[1].strip rescue nil
project = Project.find_by_full_path('root/addressbook')
if project && root_password
  var = project.variables.find_or_initialize_by(key: 'STABLE_REGISTRY_TOKEN')
  var.update!(value: root_password, protected: false, masked: true)
  puts 'SUCCESS: STABLE_REGISTRY_TOKEN set'
end
" > /dev/null 2>&1
EOSSH

    # Configuration des fichiers de pipeline et tests
    print_section "Injection des variables d'infrastructure dans GitLab..."
    
    # Liste des variables à injecter
    declare -A CI_VARS
    CI_VARS=(
        ["GITLAB_IP"]="${IP_GITLAB}"
        ["MASTER_IP"]="${IP_INFRA1}"
        ["WORKER1_IP"]="${IP_INFRA2}"
        ["WORKER2_IP"]="${IP_INFRA3}"
        ["SSH_PASS"]="${SSH_PASSWORD}"
        ["CI_REGISTRY"]="${IP_GITLAB}:5050"
    )

    for KEY in "${!CI_VARS[@]}"; do
        VALUE="${CI_VARS[$KEY]}"
        # On tente un POST (création), si ça échoue (déjà existant), on fait un PUT (mise à jour)
        curl -s -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
            "http://${IP_GITLAB}/api/v4/projects/root%2Faddressbook/variables" \
            --data "key=${KEY}&value=${VALUE}" > /dev/null
        
        curl -s -X PUT -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
            "http://${IP_GITLAB}/api/v4/projects/root%2Faddressbook/variables/${KEY}" \
            --data "value=${VALUE}" > /dev/null
    done
    
    print_success "Variables d'infrastructure injectées via API"

    print_section "Configuration de la variable CI SSH_PRIVATE_KEY..."
    
    # Attendre que GitLab soit prêt
    sleep 10
    
    # Retry loop pour la configuration de la variable
    for attempt in {1..3}; do
        # Configuration via gitlab-rails runner avec heredoc pour la sécurité des quotes
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${IP_GITLAB} <<'EOSSH'
          set -e
          # Préparer le fichier de clé temporaire
          sudo cp /home/gitlab-runner/.ssh/id_rsa /tmp/id_rsa.tmp
          sudo chmod 644 /tmp/id_rsa.tmp
          
          # Injecter via gitlab-rails
          sudo gitlab-rails runner "
            project = Project.find_by_full_path('root/addressbook')
            if project
              key_content = File.read('/tmp/id_rsa.tmp')
              variable = project.variables.find_or_initialize_by(key: 'SSH_PRIVATE_KEY')
              variable.update!(value: key_content, variable_type: 'file', protected: false, masked: false)
              puts 'SUCCESS: SSH_PRIVATE_KEY variable set'
            else
              puts 'ERROR: Project not found'
              exit 1
            end
          "
          sudo rm -f /tmp/id_rsa.tmp
EOSSH
        then
            print_success "Variable SSH_PRIVATE_KEY configurée dans GitLab"
            break
        else
            if [ $attempt -lt 3 ]; then
                print_info "Projet non trouvé, nouvel essai dans 15s... ($attempt/3)"
                sleep 15
            else
                print_error "Échec de la configuration de la variable SSH_PRIVATE_KEY après 3 tentatives"
                print_info "Tu peux configurer manuellement la variable dans GitLab > Settings > CI/CD > Variables"
            fi
        fi
    done

    # Ajout de la clé SSH à GitLab via l'API
    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
    if [ ! -f "$SSH_KEY_PATH" ]; then
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    fi
    SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
    curl -s -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
        "http://${IP_GITLAB}/api/v4/user/keys" \
        -d "title=SAE-Key-$(date +%s)" \
        --data-urlencode "key=${SSH_PUBLIC_KEY}" > /dev/null

    # Configuration SSH locale pour GitLab
    mkdir -p ~/.ssh
    if ! grep -q "Host ${IP_GITLAB}" ~/.ssh/config 2>/dev/null; then
        cat >> ~/.ssh/config <<EOF

# GitLab SAE - Auto-généré
Host ${IP_GITLAB}
    HostName ${IP_GITLAB}
    User git
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
        chmod 600 ~/.ssh/config
    fi

    print_section "Push du code Python vers GitLab..."
    
    # Lever la protection de la branche main pour permettre le force push
    curl -s -X DELETE -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
        "http://${IP_GITLAB}/api/v4/projects/root%2Faddressbook/protected_branches/main" > /dev/null

    # Initialiser et pousser le code
    cd "$SCRIPT_DIR/python"
    
    # Nettoyage pour repartir sur du propre (comme dans git-push.sh)
    rm -rf .git
    
    git init --initial-branch=main
    git config user.name "Administrator"
    git config user.email "admin@gitlab.local"
    
    git add .
    git commit -m "Initial commit - AddressBook with CI/CD" >/dev/null 2>&1 || true
    
    git remote add origin git@${IP_GITLAB}:root/addressbook.git
    
    # Push via SSH sans masquer les erreurs pour le debug
    print_info "Tentative de push vers git@${IP_GITLAB}:root/addressbook.git..."
    if git push -u origin main --force; then
        print_success "Code poussé vers GitLab (via SSH)"
    else
        print_error "Échec du push. Vérifiez la connexion SSH."
    fi
    
    cd "$SCRIPT_DIR"
    
    print_section "Configuration des tags du runner..."
    
    # Mettre à jour le runner avec les tags docker et deployment
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ${SSH_USER}@${IP_GITLAB} <<'EOSSH'
# Récupérer le token du runner et le re-register avec les bons tags
RUNNER_TOKEN=$(sudo grep -oP 'token = "\K[^"]+' /etc/gitlab-runner/config.toml | head -1)
if [ -n "$RUNNER_TOKEN" ]; then
    sudo sed -i 's/tags = \[.*\]/tags = ["docker", "deployment"]/' /etc/gitlab-runner/config.toml
    sudo gitlab-runner restart
fi
EOSSH
    
    print_success "Pipeline CI/CD configuré !"
    
    sleep 3
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Pipeline CI/CD prêt !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Pour déclencher le pipeline:"
    echo "  1. Accédez à GitLab: http://${IP_GITLAB}"
    echo "  2. Connectez-vous (root / voir mot de passe ci-dessous)"
    echo "  3. Projet: root/addressbook"
    echo "  4. Le pipeline démarre automatiquement sur chaque push"
    echo ""
}

# ============================================================================
# ÉTAPE 11 : AFFICHAGE DES INFORMATIONS FINALES
# ============================================================================

display_final_info() {
    print_title "Déploiement terminé"
    
    cat > "$SCRIPT_DIR/deployment-info.txt" <<EOF
═══════════════════════════════════════════════════════════
  SAE6.devcloud.01 - Informations de déploiement
═══════════════════════════════════════════════════════════
Date : $(date)

URLS D'ACCÈS
─────────────────────────────────────────────────────────
GitLab        : http://${IP_GITLAB}
Registry      : http://${IP_GITLAB}:5050
Application   : http://${IP_INFRA1}:30080
Proxmox       : https://${PROXMOX_HOST}:8006

CONNEXIONS SSH
─────────────────────────────────────────────────────────────
Proxmox       : ssh ${PROXMOX_USER}@${PROXMOX_HOST}
GitLab VM     : ssh ${SSH_USER}@${IP_GITLAB}
K8s Master    : ssh ${SSH_USER}@${IP_INFRA1}
K8s Worker 1  : ssh ${SSH_USER}@${IP_INFRA2}
K8s Worker 2  : ssh ${SSH_USER}@${IP_INFRA3}

Mot de passe SSH : ${SSH_PASSWORD}

MOT DE PASSE GITLAB
─────────────────────────────────────────────────────────
Pour récupérer le mot de passe root GitLab :
  ssh ${SSH_USER}@${IP_GITLAB} 'sudo cat /etc/gitlab/initial_root_password'

VÉRIFICATIONS
─────────────────────────────────────────────────────────
# Cluster Kubernetes
ssh ${SSH_USER}@${IP_INFRA1} 'kubectl get nodes'
ssh ${SSH_USER}@${IP_INFRA1} 'kubectl get pods -A'

# GitLab
ssh ${SSH_USER}@${IP_GITLAB} 'sudo gitlab-ctl status'

# Application
curl http://${IP_INFRA1}:30080/addresses/

🚀 CI/CD GITLAB
─────────────────────────────────────────────────────────
URL Projet    : http://${IP_GITLAB}/root/addressbook
Pipelines     : http://${IP_GITLAB}/root/addressbook/-/pipelines
Registry      : http://${IP_GITLAB}/root/addressbook/container_registry

Le pipeline se déclenche automatiquement à chaque push sur main.
Fichier CI/CD : python/.gitlab-ci.yml

NETTOYAGE
─────────────────────────────────────────────────────────
Pour détruire l'infrastructure :
  cd terraform && terraform destroy -auto-approve

═══════════════════════════════════════════════════════════
EOF
    
    cat "$SCRIPT_DIR/deployment-info.txt"
    
    print_success "Informations sauvegardées dans deployment-info.txt"
}

# ============================================================================
# FONCTION PRINCIPALE
# ============================================================================

main() {
    clear
    echo ""
    echo -e "${MAGENTA}"
    cat << "EOF"
 ╔═══════════════════════════════════════════════════════╗
 ║                                                       ║
 ║       SAE6.devcloud.01 - Déploiement                ║
 ║                                                       ║
 ║   Infrastructure CI/CD sur Proxmox                  ║
 ║   - 1 VM GitLab (code + registry)                   ║
 ║   - 3 VMs Kubernetes (1 master + 2 workers)         ║
 ║                                                       ║
 ╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Étapes du déploiement
    collect_configuration
    check_prerequisites
    test_proxmox_connection
    setup_proxmox_and_template
    generate_terraform_config
    deploy_infrastructure
    discover_ips
    generate_ansible_inventory
    wait_for_vms
    configure_vms
    setup_cicd_pipeline
    display_final_info
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}    DÉPLOIEMENT RÉUSSI ET TERMINÉ !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    exit 0
}

# Gestion des erreurs
trap 'print_error "Erreur durant le déploiement"; exit 1' ERR

# Lancement
main
