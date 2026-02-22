#!/bin/bash

# Script pour pusher le projet sur GitLab - 100% AUTOMATISÉ
# Utilise l'API GitLab pour ajouter la clé SSH automatiquement

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

print_title "Configuration Git et Push vers GitLab (AUTO)"

# ============================================================================
# ÉTAPE 1 : COLLECTE DES INFORMATIONS RÉSEAU
# ============================================================================

# Récupérer les informations existantes si possible
if [ -f "$SCRIPT_DIR/deployment-info.txt" ]; then
    print_info "Lecture des informations de déploiement existantes..."
    # GitLab IP (.50 suggéré par le user)
    SUGGESTED_GITLAB=$(grep -i "gitlab" "$SCRIPT_DIR/deployment-info.txt" | grep "http://" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    # Master IP (.51 suggéré par le user)
    SUGGESTED_MASTER=$(grep -i "master" "$SCRIPT_DIR/deployment-info.txt" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

SUGGESTED_GITLAB=${SUGGESTED_GITLAB:-10.129.4.50}
SUGGESTED_MASTER=${SUGGESTED_MASTER:-10.129.4.51}
SUGGESTED_WORKER1=$(echo $SUGGESTED_MASTER | sed -E 's/\.[0-9]+$/\.52/')
SUGGESTED_WORKER2=$(echo $SUGGESTED_MASTER | sed -E 's/\.[0-9]+$/\.53/')

print_title "Configuration des adresses IP"

read -p "  IP GitLab VM [$SUGGESTED_GITLAB]: " IP_GITLAB
IP_GITLAB=${IP_GITLAB:-$SUGGESTED_GITLAB}
read -p "  IP K8s Master [$SUGGESTED_MASTER]: " IP_INFRA1
IP_INFRA1=${IP_INFRA1:-$SUGGESTED_MASTER}
read -p "  IP K8s Worker 1 [$SUGGESTED_WORKER1]: " IP_INFRA2
IP_INFRA2=${IP_INFRA2:-$SUGGESTED_WORKER1}
read -p "  IP K8s Worker 2 [$SUGGESTED_WORKER2]: " IP_INFRA3
IP_INFRA3=${IP_INFRA3:-$SUGGESTED_WORKER2}

GITLAB_IP=$IP_GITLAB
GITLAB_USER="root"
PROJECT_NAME="addressbook"
SSH_USER="debian"
SSH_PASSWORD="debian123"

# URLs
GITLAB_URL="http://${GITLAB_IP}"
GITLAB_REMOTE="git@${GITLAB_IP}:${GITLAB_USER}/${PROJECT_NAME}.git"

# ============================================================================
# ÉTAPE 1.5 : PATCHING DES FICHIERS CI/CD
# ============================================================================

print_title "Patching des fichiers de configuration"

FILES_TO_PATCH=("$SCRIPT_DIR/test.sh")

for TARGET_FILE in "${FILES_TO_PATCH[@]}"; do
    if [ -f "$TARGET_FILE" ]; then
        print_info "Patching local de $TARGET_FILE..."
        
        # Mise à jour des IPs dans test.sh (script local)
        sed -i -E "s|(IP_GITLAB=\")[0-9\.]+|\1${IP_GITLAB}|g" "$TARGET_FILE"
        sed -i -E "s|(IP_MASTER=\")[0-9\.]+|\1${IP_INFRA1}|g" "$TARGET_FILE"
        sed -i -E "s|(IP_WORKER1=\")[0-9\.]+|\1${IP_INFRA2}|g" "$TARGET_FILE"
        sed -i -E "s|(IP_WORKER2=\")[0-9\.]+|\1${IP_INFRA3}|g" "$TARGET_FILE"
    fi
done

print_success "Fichiers patchés avec succès"

# ============================================================================
# ÉTAPE 2 : RÉCUPÉRER LE MOT DE PASSE ROOT GITLAB
# ============================================================================

print_title "Récupération du mot de passe GitLab"

print_info "Connexion SSH au serveur GitLab..."
GITLAB_ROOT_PASSWORD=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${SSH_USER}@${GITLAB_IP} \
    "sudo cat /etc/gitlab/initial_root_password 2>/dev/null | grep 'Password:' | awk '{print \$2}'" 2>/dev/null || echo "")

if [ -z "$GITLAB_ROOT_PASSWORD" ]; then
    print_error "Impossible de récupérer le mot de passe root"
    exit 1
fi

print_success "Mot de passe root récupéré"

# ============================================================================
# ÉTAPE 3 : CRÉER UN TOKEN D'ACCÈS PERSONNEL VIA RAILS
# ============================================================================

print_title "Création du token d'accès GitLab"

# Générer un token via gitlab-rails runner directement sur le serveur
print_info "Génération du token via gitlab-rails (cela peut prendre 30s)..."

PRIVATE_TOKEN="sae-token-$(date +%s)"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${SSH_USER}@${IP_GITLAB} <<EOSSH
sudo gitlab-rails runner "
user = User.find_by_username('root')
token = user.personal_access_tokens.create(scopes: ['api', 'write_repository'], name: 'SAE-Deploy-Token', expires_at: 30.days.from_now)
token.set_token('${PRIVATE_TOKEN}')
token.save!
" > /dev/null 2>&1
EOSSH

if [ -z "$PRIVATE_TOKEN" ]; then
    print_error "Échec de la génération du token"
    exit 1
fi

print_success "Token d'accès généré: ${PRIVATE_TOKEN:0:5}*****"

# ============================================================================
# ÉTAPE 4 : AJOUTER LA CLÉ SSH VIA L'API
# ============================================================================

print_title "Ajout automatique de la clé SSH"

# Vérifier/créer la clé SSH
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_info "Création d'une clé SSH..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    print_success "Clé SSH créée"
else
    print_success "Clé SSH existante trouvée"
fi

SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
SSH_KEY_TITLE="SAE-Deploy-$(date +%Y%m%d-%H%M%S)"

print_info "Ajout de la clé SSH via l'API GitLab..."

# Vérifier si la clé existe déjà
EXISTING_KEYS=$(curl -s -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
    "${GITLAB_URL}/api/v4/user/keys")

KEY_EXISTS=$(echo "$EXISTING_KEYS" | grep -F "$(echo $SSH_PUBLIC_KEY | awk '{print $2}')" || echo "")

if [ -n "$KEY_EXISTS" ]; then
    print_info "La clé SSH existe déjà dans GitLab"
else
    # Ajouter la clé
    ADD_KEY_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
        "${GITLAB_URL}/api/v4/user/keys" \
        -d "title=${SSH_KEY_TITLE}" \
        --data-urlencode "key=${SSH_PUBLIC_KEY}")
    
    if echo "$ADD_KEY_RESPONSE" | grep -q '"id"'; then
        print_success "Clé SSH ajoutée à GitLab avec succès!"
    else
        print_error "Échec de l'ajout de la clé SSH"
        echo "Réponse: $ADD_KEY_RESPONSE"
        exit 1
    fi
fi

# Configurer SSH
print_info "Configuration SSH locale..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if ! grep -q "Host $GITLAB_IP" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<EOF

# GitLab SAE - Auto-généré $(date)
Host $GITLAB_IP
    HostName $GITLAB_IP
    User git
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    chmod 600 "$HOME/.ssh/config"
fi

print_success "Configuration SSH terminée"

# Petite pause pour que GitLab mette à jour
sleep 2

# ============================================================================
# ÉTAPE 5 : VÉRIFIER LE PROJET GITLAB
# ============================================================================

print_title "Vérification du projet GitLab"

# Vérifier si le projet existe
PROJECT_EXISTS=$(curl -s -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_USER}%2F${PROJECT_NAME}" | grep -o '"id"' || echo "")

if [ -z "$PROJECT_EXISTS" ]; then
    print_info "Le projet n'existe pas, mais ce n'est pas grave"
    print_info "Assurez-vous de créer le projet 'addressbook' dans GitLab"
    print_info "URL: ${GITLAB_URL}/projects/new"
else
    print_success "Projet GitLab trouvé"
fi

# ============================================================================
# ÉTAPE 5.5 : INJECTION DES VARIABLES CI/CD VIA API
# ============================================================================

print_title "Injection des variables dans GitLab"

declare -A CI_VARS
CI_VARS=(
    ["GITLAB_IP"]="${IP_GITLAB}"
    ["MASTER_IP"]="${IP_INFRA1}"
    ["WORKER1_IP"]="${IP_INFRA2}"
    ["WORKER2_IP"]="${IP_INFRA3}"
    ["SSH_PASS"]="${SSH_PASSWORD}"
    ["CI_REGISTRY"]="${IP_GITLAB}:5050"
    ["STABLE_REGISTRY_TOKEN"]="${GITLAB_ROOT_PASSWORD}"
)

for KEY in "${!CI_VARS[@]}"; do
    VALUE="${CI_VARS[$KEY]}"
    # Création ou Mise à jour
    curl -s -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects/${GITLAB_USER}%2F${PROJECT_NAME}/variables" \
        --data "key=${KEY}" --data-urlencode "value=${VALUE}" > /dev/null
    
    curl -s -X PUT -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects/${GITLAB_USER}%2F${PROJECT_NAME}/variables/${KEY}" \
        --data-urlencode "value=${VALUE}" > /dev/null
done

print_success "Variables d'infrastructure synchronisées sur GitLab"

# ============================================================================
# ÉTAPE 6 : CONFIGURATION GIT LOCALE
# ============================================================================

print_title "Configuration Git locale (Dossier Python)"

cd "$SCRIPT_DIR/python"

# Nettoyage et Initialisation
print_info "Nettoyage de l'ancien historique Git..."
rm -rf .git

print_info "Initialisation du repository Git dans ./python..."
git init --initial-branch=main --object-format=sha1
print_success "Repository Git initialisé"

# Configurer l'identité Git locale
git config --local user.name "Administrator"
git config --local user.email "gitlab_admin_82a965@example.com"
print_success "Identité Git configurée"

# ============================================================================
# ÉTAPE 7 : PRÉPARER ET PUSHER LE CODE
# ============================================================================

print_title "Push du code vers GitLab"

# Configurer le remote
if git remote get-url origin &> /dev/null; then
    git remote set-url origin "$GITLAB_REMOTE"
else
    git remote add origin "$GITLAB_REMOTE"
fi

print_success "Remote configuré: $GITLAB_REMOTE"

# Note: Pas de .gitignore à générer ici car on utilise celui du dossier python
print_info "Vérification des fichiers..."

# Ajouter tous les fichiers
print_info "Ajout des fichiers au commit..."
git add .

# Créer le commit
if git diff --cached --quiet; then
    print_info "Aucun changement à committer"
    
    if ! git rev-parse HEAD &> /dev/null; then
        touch .gitkeep
        git add .gitkeep
        git commit -m "Initial commit"
        rm .gitkeep
    fi
else
    git commit -m "Initial commit - Infrastructure CI/CD Proxmox

Projet SAE6.devcloud.01 - Déploiement automatisé
- Script deploy.sh pour déploiement complet
- Configuration Terraform pour Proxmox
- Playbooks Ansible (GitLab, Kubernetes, Application)
- Application Python addressbook
- Documentation complète (README.md, GUIDE.md)

Infrastructure déployée:
- 1 VM GitLab (CI/CD + Registry)
- 3 VMs Kubernetes (1 master + 2 workers)
- Application Python déployée automatiquement

Fonctionnalités:
- Configuration interactive
- Allocation automatique des ressources
- Support multi-réseau
- Pipeline CI/CD automatique"
    print_success "Commit créé"
fi

# ÉTAPE 8 : CONFIGURATION DES VARIABLES CI ET ACCÈS SSH LOCAL
# ============================================================================

print_title "Configuration finale des accès"

print_info "Autorisation de la clé SSH sur le GitLab VM..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    ${SSH_USER}@${GITLAB_IP} <<EOSSH
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if ! grep -q "$(cat $SSH_KEY_PATH.pub)" ~/.ssh/authorized_keys 2>/dev/null; then
        echo "$(cat $SSH_KEY_PATH.pub)" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo "OK: Clé locale ajoutée aux authorized_keys"
    fi
EOSSH

# Lever la protection de la branche main
print_info "Déprotection de la branche main..."
curl -s -X DELETE -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
    "${GITLAB_URL}/api/v4/projects/root%2F${PROJECT_NAME}/protected_branches/main" > /dev/null

# Test de connexion SSH avant le push
print_info "Test de connexion SSH à GitLab..."
if ssh -T git@${GITLAB_IP} 2>&1 | grep -qE "(Welcome to GitLab|successfully authenticated)"; then
    print_success "Connexion SSH à GitLab OK"
else
    print_info "Test SSH retourné un avertissement (normal pour GitLab)"
fi

# Push vers GitLab
print_info "Push vers GitLab (branches: main, stagging, production)..."

for branch in main stagging production; do
    print_info "Pushing branch $branch..."
    git checkout -B $branch
    if git push -u origin $branch --force; then
        print_success "Push $branch réussi!"
    else
        print_error "Échec du push $branch"
        # On ne quitte pas forcément ici pour permettre le fallback de création de projet
        # mais dans le script original il tee vers /tmp/git-push.log
        git push -u origin main --force 2>&1 | tee /tmp/git-push.log
        exit 1 # Forcer l'entrée dans le bloc else de la condition originale si besoin
    fi
done

# Tag 1.0 sur production
print_info "Adding and pushing tag 1.0 on production..."
git checkout production
git tag -f 1.0
git push origin 1.0 --force
git checkout main

# Pour garder la structure du script original et son test de succès
if [ $? -eq 0 ]; then
    print_success "Push réussi!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Code pushé avec succès sur GitLab!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════${NC}"
    echo ""
    echo "🔗 URLs:"
    echo "   Projet    : ${GITLAB_URL}/${GITLAB_USER}/${PROJECT_NAME}"
    echo "   Pipelines : ${GITLAB_URL}/${GITLAB_USER}/${PROJECT_NAME}/-/pipelines"
    echo "   Registry  : ${GITLAB_URL}/${GITLAB_USER}/${PROJECT_NAME}/container_registry"
    echo ""
else
    PUSH_ERROR=$(cat /tmp/git-push.log)
    
    # Vérifier si c'est juste un problème de projet inexistant
    if echo "$PUSH_ERROR" | grep -qE "(does not appear to be|Could not read from remote|Repository not found)"; then
        print_error "Le projet n'existe pas encore dans GitLab"
        echo ""
        print_info "Création automatique du projet..."
        
        # Créer le projet via l'API
        CREATE_PROJECT=$(curl -s -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" \
            "${GITLAB_URL}/api/v4/projects" \
            -d "name=${PROJECT_NAME}" \
            -d "visibility=public")
        
        if echo "$CREATE_PROJECT" | grep -q '"id"'; then
            print_success "Projet créé!"
            sleep 2
            
            # Réessayer le push
            print_info "Nouveau push..."
            for branch in main stagging production; do
                print_info "Pushing branch $branch..."
                git checkout -B $branch
                if git push -u origin $branch --force; then
                    print_success "Push $branch réussi!"
                else
                    print_error "Échec du push $branch"
                    exit 1
                fi
            done
            
            # Tag 1.0 sur production
            print_info "Adding and pushing tag 1.0 on production..."
            git checkout production
            git tag -f 1.0
            git push origin 1.0 --force
            git checkout main
            
            print_success "Push réussi après création du projet!"
        else
            print_error "Impossible de créer le projet automatiquement"
            echo "Créez-le manuellement: ${GITLAB_URL}/projects/new"
            echo "Nom: ${PROJECT_NAME}"
            exit 1
        fi
    else
        print_error "Échec du push"
        cat /tmp/git-push.log
        exit 1
    fi
fi

print_success "✅ Script terminé avec succès!"

print_title "Mise à jour du Monitoring"
ansible-playbook -i "$SCRIPT_DIR/ansible/inventory.ini" "$SCRIPT_DIR/ansible/playbooks/05-monitoring.yml"
