# gitops-eggcatcher

GitOps configuration repository for **PakTech Egg Catcher**.
This is the single source of truth that Argo CD watches and reconciles to AKS.

> ⚠️ **Do not apply manifests manually with `kubectl apply`** (except `bootstrap.sh` and `bootstrap-monitoring.sh`).
> All changes go through Git → Argo CD reconciles automatically within 3 minutes.

**App Repo:** [PakTechLimited/app-eggcatcher](https://github.com/PakTechLimited/app-eggcatcher)  
**Live URL:** https://eggscore.paktechlimited.com

---

## Repository Structure

```
gitops-eggcatcher/
├── bootstrap.sh                         # One-time: install Argo CD + create secrets + register repo
├── bootstrap-monitoring.sh              # One-time: install Prometheus + Grafana + AlertManager
└── apps/
    ├── eggcatcher/                      # Main application Helm chart
    │   ├── Chart.yaml                   # Chart metadata
    │   ├── values.yaml                  # All config — NO secrets (image tag updated by CI)
    │   ├── argocd-app.yaml              # Argo CD Application definition
    │   └── templates/
    │       ├── postgres.yaml            # PostgreSQL StatefulSet + headless Service + PVC
    │       ├── redis.yaml               # Redis StatefulSet + headless Service + PVC
    │       ├── deployment.yaml          # Flask Deployment + ClusterIP Service (init containers)
    │       ├── ingress.yaml             # NGINX Ingress + TLS (cert-manager annotation)
    │       └── migration-job.yaml       # DB migration Job (db.create_all())
    └── monitoring/                      # kube-prometheus-stack
        ├── Chart.yaml                   # Helm chart with kube-prometheus-stack dependency
        ├── values.yaml                  # Prometheus + Grafana + AlertManager config
        ├── argocd-app.yaml              # Argo CD Application for monitoring
        ├── charts/                      # Helm dependency (committed to Git for Argo CD)
        └── raw/                         # Applied directly via kubectl (not Helm templates)
            ├── prometheus-rules.yaml    # Custom alert rules (8 rules)
            ├── grafana-dashboard.yaml   # PakTech Egg Catcher dashboard ConfigMap
            └── argocd-notifications.yaml # Argo CD Slack notification templates
```

---

## How It Works

```
Developer pushes to app-eggcatcher (main)
    │
    ▼
GitHub Actions CI/CD
    ├── pytest (14 tests, fakeredis + SQLite)
    ├── docker build + push → acreggcatcherdev.azurecr.io/eggcatcher:{run}-{sha}
    └── git commit → gitops-eggcatcher/apps/eggcatcher/values.yaml (image tag)
    │
    ▼
Argo CD detects values.yaml change (polls every 3 min)
    │
    ▼
Rolling update (zero downtime, maxUnavailable=0):
    ├── New pods start (init containers wait for Postgres + Redis)
    ├── New pods pass /health/ready probe
    └── Old pods terminate
```

---

## Prerequisites

- AKS cluster running (`aks-eggcatcher-dev` in `rg-eggcatcher-aks-dev`)
- kubectl configured: `az aks get-credentials --resource-group rg-eggcatcher-aks-dev --name aks-eggcatcher-dev`
- NGINX Ingress Controller installed (Phase 2 Terraform)
- cert-manager installed with ClusterIssuers (Phase 2 Terraform + `cluster-issuers.yaml`)
- Namespaces created: `eggcatcher`, `ingress-nginx`, `cert-manager` (Phase 2 Terraform)

---

## First-Time Setup

### Step 1 — Clone this repo

```bash
git clone https://github.com/PakTechLimited/gitops-eggcatcher.git
cd gitops-eggcatcher
```

### Step 2 — Create the app secret (never stored in Git)

```bash
kubectl create secret generic eggcatcher-secrets \
  --namespace eggcatcher \
  --from-literal=POSTGRES_PASSWORD='YourStrongPassword' \
  --from-literal=POSTGRES_USER='eggcatcher' \
  --from-literal=POSTGRES_DB='eggcatcher_db' \
  --from-literal=DATABASE_URL='postgresql://eggcatcher:YourStrongPassword@postgres:5432/eggcatcher_db' \
  --from-literal=REDIS_URL='redis://redis:6379/0' \
  --from-literal=SECRET_KEY='your-flask-secret-key'
```

> ⚠️ Use **single quotes** — bash will expand `!` in double-quoted strings,
> corrupting values like `EggCatcher2026!`.

### Step 3 — Bootstrap Argo CD

```bash
bash bootstrap.sh
# Prompts for:
#   - GitHub PAT (repo read scope on gitops-eggcatcher)
# Installs Argo CD, registers this repo, creates the Application
```

### Step 4 — Verify the app is running

```bash
kubectl get pods -n eggcatcher
# Expected:
# eggcatcher-xxxxx   1/1  Running  (x2)
# eggcatcher-db-migrate-xxxxx  0/1  Completed
# postgres-0         1/1  Running
# redis-0            1/1  Running

kubectl get ingress -n eggcatcher
# Expected: eggcatcher  nginx  eggscore.paktechlimited.com  <IP>  80, 443

kubectl get certificate -n eggcatcher
# Expected: eggcatcher-tls  True  eggcatcher-tls
```

---

## Monitoring Setup

### Step 1 — Bootstrap monitoring stack

```bash
bash bootstrap-monitoring.sh
# Installs kube-prometheus-stack via Helm (through Argo CD)
# Creates AlertManager Slack secret
# Applies PrometheusRules + Grafana dashboard + Argo CD notifications
```

### Step 2 — Apply raw manifests (not managed by Helm)

```bash
kubectl apply -f apps/monitoring/raw/prometheus-rules.yaml
kubectl apply -f apps/monitoring/raw/grafana-dashboard.yaml
kubectl apply -f apps/monitoring/raw/argocd-notifications.yaml
```

> These files are in `raw/` instead of `templates/` because they contain
> `{{ }}` syntax (Prometheus template variables, Grafana JSON) that Helm
> would try to parse as Go templates, causing plan errors.

### Step 3 — Access Grafana

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Open http://localhost:3000
# Username: admin
# Password: PakTechGrafana2026!
# Dashboard: Dashboards → EggCatcher → PakTech Egg Catcher
```

### Step 4 — Verify monitoring pods

```bash
kubectl get pods -n monitoring
# Expected (all Running):
# alertmanager-prometheus-alertmanager-0   2/2
# monitoring-grafana-xxxxx                  3/3
# monitoring-kube-state-metrics-xxxxx       1/1
# monitoring-prometheus-node-exporter-xxxxx 1/1
# prometheus-operator-xxxxx                 1/1
# prometheus-prometheus-prometheus-0        2/2
```

---

## Making Changes

### Update app configuration (replicas, resources, env vars)

```bash
# Edit values.yaml
vim apps/eggcatcher/values.yaml

git add apps/eggcatcher/values.yaml
git commit -m "config: increase flask replicas to 3"
git push
# Argo CD syncs within 3 minutes
```

### Rollback to a previous image

In Argo CD UI: **History and Rollback** → select a previous revision → **Rollback**.

Or via CLI:
```bash
argocd app rollback eggcatcher <revision-number>
```

### Force an immediate sync

```bash
kubectl patch application eggcatcher -n argocd \
  --type merge \
  -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {"revision": "HEAD"}}}'
```

---

## Argo CD Access

```bash
# Port-forward the Argo CD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080 (accept self-signed cert)
# Username: admin
# Password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## StatefulSet Details

### PostgreSQL (postgres-0)

| Property | Value |
|----------|-------|
| Image | postgres:16-alpine |
| Storage | 5Gi Azure Disk (managed-csi StorageClass) |
| Service | Headless — DNS: `postgres-0.postgres.eggcatcher.svc.cluster.local` |
| Init container | `fix-permissions` — `chown -R 999:999 /var/lib/postgresql/data` |
| Readiness probe | `pg_isready -U eggcatcher -d eggcatcher_db` |
| Data path | `/var/lib/postgresql/data/pgdata` (subdirectory to avoid mount conflicts) |

### Redis (redis-0)

| Property | Value |
|----------|-------|
| Image | redis:7-alpine |
| Storage | 1Gi Azure Disk (managed-csi StorageClass) |
| Service | Headless — DNS: `redis-0.redis.eggcatcher.svc.cluster.local` |
| Persistence | `--save 60 1` (snapshot every 60s if ≥1 key changed) |
| Readiness probe | `redis-cli ping` |

---

## Alert Rules

| Alert | Severity | Condition |
|-------|----------|-----------|
| `EggCatcherPodCrashLooping` | critical | Pod restart rate > 0 for 1 min |
| `EggCatcherHighCPU` | warning | CPU > 400m for 5 min |
| `EggCatcherHighMemory` | warning | Memory > 220Mi for 5 min |
| `PostgreSQLDown` | critical | postgres pod not ready for 1 min |
| `RedisDown` | critical | redis pod not ready for 1 min |
| `EggCatcherPodNotReady` | warning | Unavailable replicas > 0 for 2 min |
| `HighActiveSessions` | warning | Active sessions > 50 for 5 min |
| `NoScoresSubmitted` | warning | No scores in 1h for 2 hours |

All alerts route to Slack `#eggcatcher-alerts`.

---

## Slack Notifications

Two types of Slack notifications:

1. **CI/CD notifications** (from GitHub Actions) — triggered on every push to `main`
   - ✅ Green on pipeline success (image tag, commit message, live URL)
   - 🔴 Red on any job failure (which job failed, link to run)

2. **AlertManager notifications** (from Prometheus) — triggered when alert rules fire
   - Pod crashes, high CPU/memory, database down, game-specific alerts

---

## Known Issues & Fixes

### Prometheus pod Pending (Insufficient CPU)

If `prometheus-prometheus-prometheus-0` stays `Pending`:

```bash
kubectl describe pod prometheus-prometheus-prometheus-0 -n monitoring | grep -A5 "Events:"
# If "Insufficient cpu" — reduce resource requests in values.yaml:
# prometheusSpec.resources.requests.cpu: 50m (down from 200m)
```

Commit the change and force sync:

```bash
kubectl annotate application monitoring -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# If StatefulSet doesn't update, patch directly:
kubectl patch statefulset prometheus-prometheus-prometheus -n monitoring \
  --type json \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "50m"}]'
```

### Argo CD sync Unknown after gitops push

If sync status stays `Unknown` after a push to main, the Helm chart dependency
(`charts/` folder) may not be committed:

```bash
cd apps/monitoring
helm dependency update
cd ../..

# The .gitignore may block charts/ — override it:
git add -f apps/monitoring/charts/
git commit -m "feat: add helm dependency charts"
git push
```

### Argo CD stale repo secret

If Argo CD shows `Sync Status: Unknown` with repo connection errors,
the GitHub PAT may have expired. Regenerate and update:

```bash
kubectl delete secret gitops-eggcatcher-repo -n argocd
kubectl create secret generic gitops-eggcatcher-repo \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="https://github.com/PakTechLimited/gitops-eggcatcher" \
  --from-literal=username=git \
  --from-literal=password="YOUR_NEW_PAT" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - "argocd.argoproj.io/secret-type=repository" -o yaml \
  | kubectl apply -f -
```

---

## Teardown

```bash
# Remove all eggcatcher and monitoring resources from the cluster
kubectl delete application eggcatcher monitoring -n argocd

# PVCs are not deleted by Argo CD prune — delete manually if needed
kubectl delete pvc --all -n eggcatcher
kubectl delete pvc --all -n monitoring

# Argo CD itself (optional)
kubectl delete namespace argocd
```

Then destroy the Azure infrastructure from the app-eggcatcher repo:

```bash
cd app-eggcatcher/terraform && terraform destroy
az group delete --name rg-eggcatcher-aks-dev --yes --no-wait
```
