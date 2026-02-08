#!/bin/bash

# Script de nettoyage complet de l'infrastructure

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_title() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════${NC}"
    echo ""
}

print_warning() { echo -e "${YELLOW}[ATTENTION] $1${NC}"; }
print_success() { echo -e "${GREEN}[OK] $1${NC}"; }
print_error() { echo -e "${RED}[ERREUR] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
print_title "Nettoyage de l'infrastructure SAE"

echo -e "${RED}ATTENTION: Cette opération va détruire:${NC}"
echo "  - Toutes les VMs créées par Terraform (VM 100-103)"
echo "  - Le répertoire Terraform local"
echo "  - Les configurations Ansible générées"
echo ""
read -p "Êtes-vous sûr de vouloir continuer ? (oui/non): " CONFIRM

if [ "$CONFIRM" != "oui" ]; then
    echo "Opération annulée."
    exit 0
fi

echo ""
print_warning "Destruction en cours..."
echo ""

# Destruction avec Terraform
if [ -d "$SCRIPT_DIR/terraform" ] && [ -f "$SCRIPT_DIR/terraform/terraform.tfstate" ]; then
    print_warning "Destruction des VMs via Terraform..."
    cd "$SCRIPT_DIR/terraform"
    
    if terraform destroy -auto-approve 2>/dev/null; then
        print_success "VMs détruites"
    else
        print_error "Échec de la destruction Terraform (peut-être déjà détruit)"
    fi
    
    # Nettoyage des fichiers Terraform
    rm -f terraform.tfstate* .terraform.lock.hcl
    rm -rf .terraform/
    print_success "Fichiers Terraform nettoyés"
else
    print_warning "Pas de state Terraform trouvé"
fi

# Nettoyage des configurations générées
if [ -f "$SCRIPT_DIR/ansible/inventory.ini" ]; then
    rm -f "$SCRIPT_DIR/ansible/inventory.ini"
    print_success "Inventory Ansible supprimé"
fi

if [ -f "$SCRIPT_DIR/terraform/terraform.tfvars" ]; then
    rm -f "$SCRIPT_DIR/terraform/terraform.tfvars"
    print_success "Configuration Terraform supprimée"
fi

# Nettoyage du dépôt git local Python
if [ -d "$SCRIPT_DIR/python/.git" ]; then
    rm -rf "$SCRIPT_DIR/python/.git"
    print_success "Dépôt git Python nettoyé"
fi

# Nettoyage des fichiers temporaires
rm -rf /tmp/sae-deploy-* 2>/dev/null
rm -f /tmp/git-askpass.sh 2>/dev/null

echo ""
print_title "Nettoyage terminé"
echo ""
echo "Infrastructure complètement nettoyée."
echo "Vous pouvez relancer ./deploy.sh pour redéployer."
echo ""
