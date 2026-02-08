#!/bin/bash

# Script pour pusher le projet sur GitLab
# Utilise les informations de deployment-info.txt si disponible

set -e
set -o pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_title "Configuration Git et Push vers GitLab"

# ============================================================================
# ÉTAPE 1 : COLLECTE DES INFORMATIONS
# ============================================================================

# Essayer de récupérer l'IP GitLab depuis deployment-info.txt
if [ -f "$SCRIPT_DIR/deployment-info.txt" ]; then
    print_info "Lecture des informations de déploiement..."
    GITLAB_IP=$(grep -i "gitlab" "$SCRIPT_DIR/deployment-info.txt" | grep "http://" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$GITLAB_IP" ]; then
        print_success "IP GitLab trouvée: $GITLAB_IP"
    fi
fi

# Demander l'IP si pas trouvée
if [ -z "$GITLAB_IP" ]; then
    read -p "Adresse IP de votre GitLab [192.168.122.41]: " GITLAB_IP
    GITLAB_IP=${GITLAB_IP:-192.168.122.41}
fi

# Informations du projet
read -p "Nom d'utilisateur GitLab [root]: " GITLAB_USER
GITLAB_USER=${GITLAB_USER:-root}

read -p "Nom du projet GitLab [addressbook]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-addressbook}

# Construire l'URL SSH du remote
GITLAB_REMOTE="git@${GITLAB_IP}:${GITLAB_USER}/${PROJECT_NAME}.git"

print_info "Remote GitLab: $GITLAB_REMOTE"
echo ""

# ============================================================================
# ÉTAPE 2 : CONFIGURATION GIT LOCALE
# ============================================================================

print_title "Configuration Git locale"

# Vérifier si git est déjà initialisé
if [ -d "$SCRIPT_DIR/.git" ]; then
    print_info "Repository Git déjà initialisé"
else
    print_info "Initialisation du repository Git..."
    cd "$SCRIPT_DIR"
    git init --initial-branch=main --object-format=sha1
    print_success "Repository Git initialisé"
fi

# Configurer l'identité Git locale
print_info "Configuration de l'identité Git locale..."
git config --local user.name "Administrator"
git config --local user.email "gitlab_admin_82a965@example.com"
print_success "Identité Git configurée"

# ============================================================================
# ÉTAPE 3 : CONFIGURATION SSH POUR GITLAB
# ============================================================================

print_title "Configuration SSH pour GitLab"

# Vérifier/créer la clé SSH
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_info "Création d'une clé SSH..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    print_success "Clé SSH créée"
else
    print_success "Clé SSH existante trouvée"
fi

# Afficher la clé publique
echo ""
print_info "Votre clé SSH publique (à ajouter dans GitLab):"
echo -e "${CYAN}$(cat ${SSH_KEY_PATH}.pub)${NC}"
echo ""

# Configurer SSH pour accepter la connexion à GitLab
print_info "Configuration SSH pour GitLab..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Ajouter la config SSH pour GitLab si elle n'existe pas
if ! grep -q "Host $GITLAB_IP" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<EOF

# GitLab SAE
Host $GITLAB_IP
    HostName $GITLAB_IP
    User git
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    chmod 600 "$HOME/.ssh/config"
    print_success "Configuration SSH ajoutée"
else
    print_info "Configuration SSH déjà présente"
fi

# ============================================================================
# ÉTAPE 4 : AJOUTER LA CLÉ SSH À GITLAB (via SSH vers le serveur)
# ============================================================================

print_title "Ajout de la clé SSH sur GitLab"

print_info "Tentative d'ajout automatique de la clé SSH sur GitLab..."

# Lire le mot de passe root GitLab
print_info "Pour ajouter la clé SSH, nous devons copier la clé sur le serveur GitLab"
read -p "Utilisateur SSH du serveur GitLab [debian]: " GITLAB_SSH_USER
GITLAB_SSH_USER=${GITLAB_SSH_USER:-debian}

read -sp "Mot de passe SSH du serveur GitLab [debian123]: " GITLAB_SSH_PASS
GITLAB_SSH_PASS=${GITLAB_SSH_PASS:-debian123}
echo ""

# Copier la clé publique sur le serveur GitLab
SSH_PUB_KEY=$(cat ${SSH_KEY_PATH}.pub)

if command -v sshpass &> /dev/null; then
    print_info "Copie de la clé SSH sur le serveur GitLab..."
    
    sshpass -p "$GITLAB_SSH_PASS" ssh -o StrictHostKeyChecking=no \
        ${GITLAB_SSH_USER}@${GITLAB_IP} <<EOSSH
# Récupérer le token root initial
ROOT_PASSWORD=\$(sudo cat /etc/gitlab/initial_root_password 2>/dev/null | grep "Password:" | awk '{print \$2}')

if [ -z "\$ROOT_PASSWORD" ]; then
    echo "ATTENTION: Impossible de récupérer le mot de passe root"
    echo "Veuillez ajouter manuellement la clé SSH via l'interface web:"
    echo "  http://${GITLAB_IP}/-/profile/keys"
    echo ""
    echo "Clé à ajouter:"
    echo "$SSH_PUB_KEY"
else
    echo "Mot de passe root GitLab: \$ROOT_PASSWORD"
    echo ""
    echo "Pour ajouter la clé SSH:"
    echo "1. Connectez-vous à: http://${GITLAB_IP}"
    echo "2. User: root, Password: \$ROOT_PASSWORD"
    echo "3. Allez dans Profile > SSH Keys"
    echo "4. Ajoutez cette clé:"
    echo ""
    echo "$SSH_PUB_KEY"
fi
EOSSH
    
    print_success "Instructions affichées"
else
    print_error "sshpass n'est pas installé"
    print_info "Ajoutez manuellement la clé SSH via: http://${GITLAB_IP}/-/profile/keys"
    echo ""
    echo "Clé à ajouter:"
    echo -e "${CYAN}$SSH_PUB_KEY${NC}"
fi

echo ""
read -p "Appuyez sur ENTRÉE une fois la clé SSH ajoutée dans GitLab..."

# ============================================================================
# ÉTAPE 5 : TESTER LA CONNEXION SSH
# ============================================================================

print_title "Test de connexion SSH à GitLab"

print_info "Test de connexion à git@${GITLAB_IP}..."

if ssh -T git@${GITLAB_IP} 2>&1 | grep -q "Welcome to GitLab"; then
    print_success "Connexion SSH à GitLab réussie!"
else
    print_error "Échec de la connexion SSH"
    print_info "Vérifiez que la clé SSH est bien ajoutée dans GitLab"
    print_info "Vous pouvez continuer quand même et voir les erreurs..."
    read -p "Continuer quand même? (y/N): " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# ÉTAPE 6 : AJOUTER LE REMOTE ET PUSHER
# ============================================================================

print_title "Push du code vers GitLab"

cd "$SCRIPT_DIR"

# Configurer le remote
if git remote get-url origin &> /dev/null; then
    print_info "Remote origin existe déjà, mise à jour..."
    git remote set-url origin "$GITLAB_REMOTE"
else
    print_info "Ajout du remote origin..."
    git remote add origin "$GITLAB_REMOTE"
fi

print_success "Remote configuré: $GITLAB_REMOTE"

# Vérifier le .gitignore
if [ ! -f "$SCRIPT_DIR/.gitignore" ]; then
    print_info "Création du .gitignore..."
    cat > "$SCRIPT_DIR/.gitignore" <<'EOF'
# Terraform
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/terraform.tfvars

# Ansible
ansible/inventory.ini
ansible/*.retry

# Logs et temporaires
*.log
/tmp/
deployment-info.txt
python-app.tar.gz

# SSH
.ssh/
EOF
    print_success ".gitignore créé"
fi

# Ajouter tous les fichiers
print_info "Ajout des fichiers au commit..."
git add .

# Vérifier s'il y a des changements à committer
if git diff --cached --quiet; then
    print_info "Aucun changement à committer"
    
    # Vérifier si on a déjà des commits
    if ! git rev-parse HEAD &> /dev/null; then
        print_info "Création du commit initial..."
        echo "# SAE6.devcloud.01" > README_temp.md
        git add README_temp.md
        git commit -m "Initial commit"
        rm README_temp.md
    fi
else
    print_info "Création du commit..."
    git commit -m "Initial commit - Infrastructure CI/CD Proxmox

- Deploy script complet
- Configuration Terraform pour Proxmox
- Playbooks Ansible (GitLab, Kubernetes, App)
- Application Python addressbook
- Documentation complète"
    print_success "Commit créé"
fi

# Push vers GitLab
print_info "Push vers GitLab (main)..."

if git push --set-upstream origin main --force; then
    print_success "Push réussi!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Code pushé avec succès sur GitLab!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo "URL du projet: http://${GITLAB_IP}/${GITLAB_USER}/${PROJECT_NAME}"
    echo ""
else
    print_error "Échec du push"
    echo ""
    print_info "Diagnostic:"
    echo "1. Vérifiez que la clé SSH est bien dans GitLab: http://${GITLAB_IP}/-/profile/keys"
    echo "2. Vérifiez que le projet existe: http://${GITLAB_IP}/${GITLAB_USER}/${PROJECT_NAME}"
    echo "3. Testez manuellement: ssh -T git@${GITLAB_IP}"
    exit 1
fi

print_success "Script terminé avec succès!"
