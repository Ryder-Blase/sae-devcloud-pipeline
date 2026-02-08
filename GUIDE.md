# SAE6.devcloud.01 - Infrastructure CI/CD Complète

## Description

Déploiement automatisé complet d'une infrastructure CI/CD sur Proxmox :
- 1 VM GitLab (gestion du code + registry Docker)
- 3 VMs Kubernetes (1 master + 2 workers)
- Application AddressBook déployée
- Pipeline CI/CD automatique

## Prérequis

- Proxmox VE installé et accessible
- Template Ubuntu cloud-init créé (ID 9000)
- Accès SSH à Proxmox
- Machine de contrôle avec Ansible et Terraform installés

## Déploiement Initial

### 1. Configuration

Le script `deploy.sh` est **complètement interactif** et demande toutes les informations nécessaires :

```bash
./deploy.sh
```

Le script vous demandera :
- **IP de Proxmox** (ex: 192.168.122.227)
- **Credentials Proxmox** (user/password)
- **Configuration réseau** (IPs des VMs, gateway)
- **Ressources** (CPU, RAM disponibles)

Toutes les configurations ont des valeurs par défaut proposées.

### 2. Durée

Le déploiement complet prend environ **45 minutes** et se déroule en 8 étapes :
1. Collecte des informations
2. Génération des configurations (Terraform, Ansible)
3. Création du template cloud-init
4. Déploiement des VMs via Terraform
5. Installation de GitLab (Ansible)
6. Configuration de Kubernetes (Ansible)
7. Déploiement de l'application (Ansible)
8. Configuration du pipeline CI/CD

### 3. Zéro Intervention

Une fois lancé, **aucune intervention manuelle n'est requise**. Le script :
- Crée toutes les VMs
- Configure automatiquement tous les services
- Enregistre les runners GitLab
- Push le code dans GitLab
- Configure le pipeline CI/CD

## Accès Post-Déploiement

### GitLab
- **URL**: `http://<IP_GITLAB>`
- **User**: root
- **Password**: Affiché en fin de déploiement

### Application
- **URL**: `http://<IP_MASTER_K8S>:30080/addresses/`

### Kubernetes
- SSH vers le master: `ssh debian@<IP_MASTER_K8S>`
- Commandes kubectl disponibles immédiatement

## Scripts Disponibles

### deploy.sh - Déploiement Complet
```bash
./deploy.sh
```
Déploie toute l'infrastructure de zéro. Totalement interactif.

### test.sh - Tests de Validation
```bash
./test.sh
```
Vérifie que tous les composants sont opérationnels :
- Proxmox accessible
- VMs actives
- GitLab fonctionnel
- Kubernetes opérationnel
- Application accessible
- Pipeline configuré

### test-cicd.sh - Test Rapide CI/CD
```bash
./test-cicd.sh
```
Teste uniquement la partie CI/CD sans redéployer l'infrastructure.
Utile pour déboguer le pipeline.

### cleanup.sh - Nettoyage Complet
```bash
./cleanup.sh
```
Détruit toutes les VMs et nettoie les configurations.
Permet de repartir de zéro proprement.

## Changement d'Environnement

### Nouveau Proxmox / Nouvelles IPs

L'infrastructure est **100% dynamique**. Pour changer de Proxmox ou d'IPs :

1. **Nettoyage** :
   ```bash
   ./cleanup.sh
   ```

2. **Nouveau déploiement** :
   ```bash
   ./deploy.sh
   ```
   Le script demandera les nouvelles informations.

### Génération Automatique

Le script génère automatiquement :
- `terraform/terraform.tfvars` avec les IPs spécifiées
- `ansible/inventory.ini` avec les hosts créés
- `.gitlab-ci.yml` avec les bonnes IPs de déploiement

**Aucune modification manuelle de fichier n'est nécessaire.**

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    PROXMOX VE                       │
│  ┌────────────┐  ┌─────────────────────────────┐   │
│  │  VM 100    │  │       KUBERNETES            │   │
│  │  GitLab    │  │  ┌────────┬────────┬──────┐ │   │
│  │  + Registry│  │  │ VM 101 │ VM 102 │VM 103│ │   │
│  │  + Runners │  │  │ Master │Worker 1│Worker│ │   │
│  └────────────┘  │  └────────┴────────┴──────┘ │   │
│                  │    Application AddressBook   │   │
│                  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────┘

FLUX CI/CD:
1. Code push → GitLab
2. Pipeline déclenché (Runner Docker)
3. Build image → Push registry
4. Deploy sur K8s (Runner Shell)
5. Application mise à jour
```

## Pipeline CI/CD

Le pipeline GitLab s'exécute automatiquement à chaque push :

### Stage 1 : Build
- Runner Docker
- Build de l'image Docker Python
- Login au registry GitLab
- Push de l'image vers `<IP_GITLAB>:5050/root/addressbook:latest`

### Stage 2 : Deploy
- Runner Shell (accès SSH aux nodes K8s)
- Création du secret imagePullSecret
- Restart du deployment Kubernetes
- Vérification du rollout (timeout 120s)
- Affichage des pods déployés

## Validation SAE

### Exigences Respectées

✅ **Hyperviseur Proxmox installé**  
✅ **4 VMs créées** (1 GitLab + 3 K8s)  
✅ **GitLab déployé** avec registry Docker  
✅ **Projet injecté** automatiquement  
✅ **CI/CD configurée** avec 2 runners  
✅ **Orchestrateur Kubernetes** (3 nodes)  
✅ **Application déployée** et accessible  
✅ **Déploiement automatisé** (zéro intervention)  

### Livrables à Préparer

- **Vidéo démo** (5 min) : Montrer ./deploy.sh + application + pipeline
- **Rapport technique** : Architecture, choix techniques, scripts
- **Bilan de compétences** : Preuves d'acquisition, démarche

## Dépannage

### Les VMs ne démarrent pas
- Vérifier que le template cloud-init existe (ID 9000)
- Vérifier les ressources disponibles sur Proxmox
- Consulter les logs Terraform : `cd terraform && terraform plan`

### GitLab inaccessible
- Attendre 2-3 minutes après la création (initialisation)
- Vérifier : `ssh debian@<IP_GITLAB> "sudo gitlab-ctl status"`

### Pipeline bloqué
- Vérifier les runners : `ssh debian@<IP_GITLAB> "sudo gitlab-runner list"`
- Voir les logs : GitLab → CI/CD → Jobs

### Application inaccessible
- Vérifier les pods : `ssh debian@<IP_MASTER> "kubectl get pods -n production"`
- Voir les logs : `kubectl logs -n production -l app=addressbook`

## Support

Pour tout problème :
1. Lancer `./test.sh` pour identifier le composant en erreur
2. Consulter les logs Ansible dans `/tmp/sae-deploy-*/`
3. En dernier recours : `./cleanup.sh` puis `./deploy.sh`

## Auteur

SAE6.devcloud.01 - Infrastructure CI/CD Automatisée  
2026
