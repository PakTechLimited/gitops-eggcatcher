#!/usr/bin/env bash
# bootstrap-monitoring.sh — Install monitoring stack and wire Slack notifications
# Run from gitops-eggcatcher/ directory
set -euo pipefail

SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/YOUR_WEBHOOK_HERE}"

echo "── Step 1: Create monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "── Step 2: Add Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "── Step 3: Update Helm chart dependencies..."
cd apps/monitoring
helm dependency update
cd ../..

echo "── Step 4: Create Argo CD Slack secret..."
kubectl create secret generic argocd-notifications-secret \
  --namespace argocd \
  --from-literal=slack-token="" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "── Step 5: Create AlertManager Slack secret..."
kubectl create secret generic alertmanager-slack \
  --namespace monitoring \
  --from-literal=slack_webhook_url="${SLACK_WEBHOOK}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "── Step 6: Apply Argo CD notifications ConfigMap..."
kubectl apply -f apps/monitoring/raw/argocd-notifications.yaml

echo "── Step 7: Apply monitoring Argo CD Application..."
kubectl apply -f apps/monitoring/argocd-app.yaml

echo ""
echo "── Done! Monitoring stack deploying via Argo CD."
echo "   Watch progress:"
echo "   kubectl get pods -n monitoring --watch"
echo ""
echo "── Access Grafana (port-forward):"
echo "   kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
echo "   Open: http://localhost:3000 (admin / PakTechGrafana2026!)"
