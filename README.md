# gitops-eggcatcher

GitOps configuration repository for **PakTech Egg Catcher**.
This is the single source of truth that Argo CD watches and reconciles to AKS.

> ⚠️ Do not apply manifests manually with `kubectl apply` (except bootstrap.sh).
> All changes go through Git → Argo CD reconciles automatically.

## Repository Structure

```
gitops-eggcatcher/
├── bootstrap.sh                    # One-time setup: Argo CD + secrets
└── apps/
    └── eggcatcher/
        ├── Chart.yaml              # Helm chart metadata
        ├── values.yaml             # All configuration (no secrets)
        ├── argocd-app.yaml         # Argo CD Application definition
        └── templates/
            ├── secret.yaml         # Kubernetes Secret (values injected at deploy)
            ├── postgres.yaml       # PostgreSQL StatefulSet + headless Service + PVC
            ├── redis.yaml          # Redis StatefulSet + headless Service + PVC
            ├── deployment.yaml     # Flask app Deployment + ClusterIP Service
            ├── migration-job.yaml  # DB migration PreSync hook Job
            └── ingress.yaml        # NGINX Ingress + TLS (cert-manager)
```

## How It Works

```
Push to app-eggcatcher (main)
    │
    ▼
GitHub Actions CI
    ├── Build Docker image
    ├── Push to ACR (acreggcatcherdev.azurecr.io)
    └── Update image tag in values.yaml (this repo)
    │
    ▼
Argo CD detects values.yaml change (polls every 3 min)
    │
    ▼
PreSync: migration Job runs (db.create_all())
    │
    ▼
Sync: Deploys/updates all resources
    ├── PostgreSQL StatefulSet (stable pod: postgres-0)
    ├── Redis StatefulSet (stable pod: redis-0)
    ├── Flask Deployment (2 replicas, rolling update)
    ├── NGINX Ingress → eggscore.paktechlimited.com
    └── cert-manager issues TLS cert automatically
```

## First-Time Setup

```bash
# 1. Clone this repo
git clone https://github.com/PakTechLimited/gitops-eggcatcher
cd gitops-eggcatcher

# 2. Make sure kubectl is pointing at the right cluster
kubectl config current-context   # should be aks-eggcatcher-dev

# 3. Run bootstrap (installs Argo CD, creates secrets, registers repo)
bash bootstrap.sh
```

## Verify Deployment

```bash
# All pods running
kubectl get pods -n eggcatcher

# StatefulSets
kubectl get statefulset -n eggcatcher

# PVCs bound
kubectl get pvc -n eggcatcher

# Ingress + TLS cert
kubectl get ingress -n eggcatcher
kubectl get certificate -n eggcatcher

# Argo CD sync status
kubectl get application -n argocd
```

## Making Changes

To change any configuration (replicas, resources, env vars):

```bash
# Edit values.yaml
vim apps/eggcatcher/values.yaml

git add apps/eggcatcher/values.yaml
git commit -m "config: increase flask replicas to 3"
git push
# Argo CD syncs within 3 minutes
```

## Teardown

```bash
# Delete Argo CD app (removes all eggcatcher resources from cluster)
kubectl delete application eggcatcher -n argocd

# Then run terraform destroy in app-eggcatcher/terraform/ and terraform/aks/
```
