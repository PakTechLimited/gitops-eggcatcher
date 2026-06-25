#!/usr/bin/env bash
# bootstrap.sh — Run once to install Argo CD and wire up the eggcatcher app.
# Prerequisites: kubectl configured for aks-eggcatcher-dev
set -euo pipefail

ACR="acreggcatcherdev.azurecr.io"
GITHUB_ORG="PakTechLimited"
GITOPS_REPO="gitops-eggcatcher"

# ── 1. Install Argo CD ────────────────────────────────────────────────────────
echo "── Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "── Waiting for Argo CD pods..."
kubectl wait --for=condition=available --timeout=120s \
  deployment/argocd-server -n argocd

# ── 2. Create app secrets ─────────────────────────────────────────────────────
echo ""
echo "── Creating eggcatcher-secrets..."
echo "Enter values for the Kubernetes secret (nothing is stored in Git):"
echo ""

read -rsp "  POSTGRES_PASSWORD: " POSTGRES_PASSWORD; echo
read -rsp "  SECRET_KEY (Flask): " SECRET_KEY; echo

kubectl create secret generic eggcatcher-secrets \
  --namespace eggcatcher \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_USER="eggcatcher" \
  --from-literal=POSTGRES_DB="eggcatcher_db" \
  --from-literal=DATABASE_URL="postgresql://eggcatcher:${POSTGRES_PASSWORD}@postgres:5432/eggcatcher_db" \
  --from-literal=REDIS_URL="redis://redis:6379/0" \
  --from-literal=SECRET_KEY="${SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret created"

# ── 3. Register GitOps repo with Argo CD ─────────────────────────────────────
echo ""
echo "── Registering GitOps repo with Argo CD..."
echo "Enter a GitHub PAT with read access to ${GITHUB_ORG}/${GITOPS_REPO}:"
read -rsp "  GitHub PAT: " GITHUB_PAT; echo

kubectl create secret generic gitops-eggcatcher-repo \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="https://github.com/${GITHUB_ORG}/${GITOPS_REPO}" \
  --from-literal=username=git \
  --from-literal=password="${GITHUB_PAT}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - \
      "argocd.argoproj.io/secret-type=repository" \
      -o yaml \
  | kubectl apply -f -

echo "✅ Repo registered"

# ── 4. Apply Argo CD Application ──────────────────────────────────────────────
echo ""
echo "── Creating Argo CD Application..."
kubectl apply -f apps/eggcatcher/argocd-app.yaml
echo "✅ Application created"

# ── 5. Get Argo CD admin password ────────────────────────────────────────────
echo ""
echo "── Argo CD admin password:"
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "── Port-forward Argo CD UI (run in a new terminal):"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Open: https://localhost:8080  (admin / password above)"
echo ""
echo "── Done! Argo CD will now sync the eggcatcher app from Git."
