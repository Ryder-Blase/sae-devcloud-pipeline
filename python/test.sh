#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_test() {
    echo -e "\n${YELLOW}[TEST]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

FAILED=0
PASSED=0

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           TESTS DE VALIDATION - SAE DEVCLOUD                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# IPs Variables
IP_GITLAB="10.129.4.42"
IP_MASTER="10.129.4.43"
IP_WORKER1="10.129.4.87"
IP_WORKER2="10.129.4.58"

# Test 1: Proxmox accessible
print_test "Connexion à Proxmox"
if curl -s -k https://10.129.4.31:8006 > /dev/null 2>&1; then
    print_ok "Proxmox accessible sur https://10.129.4.31:8006"
    ((PASSED++))
else
    print_error "Proxmox non accessible"
    ((FAILED++))
fi

# Test 2: VMs actives
print_test "Vérification des VMs"
for ip in $IP_GITLAB $IP_MASTER $IP_WORKER1 $IP_WORKER2; do
    if ping -c 1 -W 2 $ip > /dev/null 2>&1; then
        print_ok "VM ($ip) répond"
        ((PASSED++))
    else
        print_error "VM ($ip) ne répond pas"
        ((FAILED++))
    fi
done

# Test 3: GitLab accessible
print_test "Vérification de GitLab"
if curl -s http://$IP_GITLAB | grep -q "GitLab"; then
    print_ok "GitLab accessible sur http://$IP_GITLAB"
    ((PASSED++))
else
    print_error "GitLab non accessible"
    ((FAILED++))
fi

# Test 4: Registry accessible
print_test "Vérification du Registry Docker"
if curl -s http://$IP_GITLAB:5050/v2/ | grep -q "{}"; then
    print_ok "Registry Docker accessible sur port 5050"
    ((PASSED++))
else
    print_error "Registry Docker non accessible"
    ((FAILED++))
fi

# Test 5: Runners enregistrés
print_test "Vérification des GitLab Runners"
RUNNERS=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@$IP_GITLAB "sudo gitlab-runner list 2>/dev/null | grep -c 'Executor'")
if [ "$RUNNERS" -ge "2" ]; then
    print_ok "$RUNNERS runners enregistrés"
    ((PASSED++))
else
    print_error "Pas assez de runners ($RUNNERS/2)"
    ((FAILED++))
fi

# Test 6: Kubernetes nodes
print_test "Vérification des nodes Kubernetes"
NODES_READY=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@$IP_MASTER "kubectl get nodes 2>/dev/null | grep -c Ready")
if [ "$NODES_READY" -eq "3" ]; then
    print_ok "3 nodes Kubernetes Ready"
    ((PASSED++))
else
    print_error "Tous les nodes ne sont pas Ready ($NODES_READY/3)"
    ((FAILED++))
fi

# Test 7: Namespace production
print_test "Vérification du namespace production"
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@$IP_MASTER "kubectl get namespace production 2>/dev/null" | grep -q "production"; then
    print_ok "Namespace production existe"
    ((PASSED++))
else
    print_error "Namespace production n'existe pas"
    ((FAILED++))
fi

# Test 8: Pods applicatifs
print_test "Vérification des pods AddressBook"
PODS_RUNNING=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@$IP_MASTER "kubectl get pods -n production -l app=addressbook 2>/dev/null | grep -c Running")
if [ "$PODS_RUNNING" -ge "1" ]; then
    print_ok "Au moins 1 pod AddressBook Running"
    ((PASSED++))
else
    print_error "Aucun pod AddressBook Running"
    ((FAILED++))
fi

# Test 9: Service NodePort
print_test "Vérification du service NodePort"
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null debian@$IP_MASTER "kubectl get svc -n production 2>/dev/null | grep addressbook-service | grep -q 30080"; then
    print_ok "Service NodePort configuré sur port 30080"
    ((PASSED++))
else
    print_error "Service NodePort non configuré"
    ((FAILED++))
fi

# Test 10: Application accessible
print_test "Vérification de l'application web"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$IP_MASTER:30080/addresses/)
if [ "$HTTP_CODE" = "200" ]; then
    print_ok "Application répond HTTP 200 sur http://$IP_MASTER:30080/addresses/"
    ((PASSED++))
else
    print_error "Application ne répond pas correctement (HTTP $HTTP_CODE)"
    ((FAILED++))
fi

# Résumé
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                        RÉSULTAT DES TESTS                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "Tests réussis: ${GREEN}$PASSED${NC}"
echo -e "Tests échoués: ${RED}$FAILED${NC}"
echo -e "Total: $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Tous les tests sont passés ! Infrastructure opérationnelle.${NC}"
    exit 0
else
    echo -e "${RED}✗ $FAILED test(s) en échec. Vérifier les composants défaillants.${NC}"
    exit 1
fi
