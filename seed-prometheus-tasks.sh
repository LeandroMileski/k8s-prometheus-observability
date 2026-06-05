
#!/usr/bin/env bash
#
# seed-prometheus-tasks.sh
# Populates the k8s-prometheus-observability repo with milestones, labels,
# and issues (each with checkbox subtasks) for the Prometheus monitoring project.
#
# Prereqs:
#   - gh CLI installed and authenticated:  gh auth login
#   - the repo already created on GitHub
#
# Usage:
#   ./seed-prometheus-tasks.sh LeandroMileski/k8s-prometheus-observability
#
set -euo pipefail
 
REPO="${1:?Usage: ./seed-prometheus-tasks.sh <owner>/<repo>}"
echo ">> Seeding $REPO"
 
# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------
create_label () {  # name, color, description
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
}
echo ">> Labels"
create_label "infra"       "1d76db" "Cluster / Terraform / bootstrap"
create_label "app-stack"   "0e8a16" "MySQL / Java / Ingress deployment"
create_label "prometheus"  "e36209" "Prometheus Operator & scraping config"
create_label "exporter"    "fbca04" "Metrics exporters"
create_label "servicemonitor" "5319e7" "ServiceMonitor / scraping CRDs"
create_label "verify"      "0052cc" "Verification & testing"
create_label "docs"        "c5def5" "Documentation & portfolio"
create_label "stretch"     "d4c5f9" "Optional / stretch goals"
 
# ---------------------------------------------------------------------------
# Milestones  (gh has no native create cmd -> use the API)
# ---------------------------------------------------------------------------
create_milestone () {  # title, description
  gh api "repos/$REPO/milestones" -f title="$1" -f description="$2" -f state="open" >/dev/null \
    || echo "   (milestone '$1' may already exist, skipping)"
}
echo ">> Milestones"
create_milestone "M0 - Repo & bootstrap"        "New repo with adapted Terraform + Ansible automation in place."
create_milestone "M1 - Base app stack"          "Cluster, replicated MySQL (2), Java (3), Nginx Ingress + rule."
create_milestone "M2 - Deploy Prometheus"       "kube-prometheus-stack (Operator) running, UI reachable."
create_milestone "M3 - Scrape Nginx Ingress"    "Native ingress-nginx metrics into Prometheus."
create_milestone "M4 - Scrape MySQL"            "mysqld-exporter via the Bitnami chart into Prometheus."
create_milestone "M5 - Scrape Java app"         "Custom ServiceMonitor on port 8081 (non-standard path)."
create_milestone "M6 - Verify in Prometheus UI" "All three custom targets confirmed UP."
create_milestone "M7 - Polish & alerting"       "Docs, reproducibility, STAR summary, proactive alerting."
 
# helper: resolve milestone number by title
ms_number () { gh api "repos/$REPO/milestones?state=all" --jq ".[] | select(.title==\"$1\") | .number"; }
 
# ---------------------------------------------------------------------------
# Issues
# ---------------------------------------------------------------------------
create_issue () {  # title, body, labels(csv), milestone-title
  gh issue create --repo "$REPO" \
    --title "$1" --body "$2" --label "$3" --milestone "$4" >/dev/null
  echo "   + $1"
}
echo ">> Issues"
 
# --- M0 -------------------------------------------------------------------
create_issue "Bootstrap the repo" \
"$(cat <<'EOF'
- [ ] Copy adapted `terraform/` and `ansible/` from the Ansible repo
- [ ] `ansible-galaxy collection install -r ansible/requirements.yml`
- [ ] README skeleton
- [ ] `.gitignore` (tfstate, tfvars, hosts.ini, vault.yml)
 
**DoD:** repo clones cleanly; `terraform validate` and `ansible --version` pass.
EOF
)" "infra,docs" "M0 - Repo & bootstrap"
 
# --- M1 -------------------------------------------------------------------
create_issue "Provision cluster + storage" \
"$(cat <<'EOF'
- [ ] Terraform apply (Linode VMs, firewall, inventory)
- [ ] Bootstrap playbook (common / control_plane / worker)
- [ ] local-path storage provisioner installed via Ansible
 
**DoD:** `kubectl get nodes` Ready; default StorageClass = local-path.
EOF
)" "infra" "M1 - Base app stack"
 
create_issue "Deploy replicated MySQL (2 replicas)" \
"$(cat <<'EOF'
- [ ] Helm: `architecture: replication`, `secondary.replicaCount: 1` (= 1 primary + 1 secondary)
- [ ] Credentials from Ansible Vault
- [ ] PVCs Bound, both pods Ready
 
**DoD:** 2 MySQL pods Running; secondary replicating.
EOF
)" "app-stack" "M1 - Base app stack"
 
create_issue "Deploy Java app (3 replicas) + Ingress" \
"$(cat <<'EOF'
- [ ] Java deployment `replicas: 3`, `DB_HOST` -> `mysql-primary`
- [ ] Nginx Ingress Controller via Helm
- [ ] Ingress rule routing to the Java service
 
**DoD:** app loads in a browser; 3 Java pods Running.
EOF
)" "app-stack" "M1 - Base app stack"
 
# --- M2 -------------------------------------------------------------------
create_issue "Deploy kube-prometheus-stack" \
"$(cat <<'EOF'
- [ ] Add `prometheus-community` Helm repo
- [ ] Ansible `monitoring` role: helm install into `monitoring` namespace
- [ ] Verify pods: Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter, operator
- [ ] Reach Prometheus UI (port-forward or NodePort)
 
**DoD:** Prometheus UI loads; default K8s targets UP.
**Note:** the Operator configures Prometheus via CRDs (ServiceMonitor/PodMonitor/PrometheusRule) — not a static config file.
EOF
)" "prometheus" "M2 - Deploy Prometheus"
 
# --- M3 -------------------------------------------------------------------
create_issue "Scrape Nginx Ingress (native metrics)" \
"$(cat <<'EOF'
Pattern: **native** — ingress-nginx speaks Prometheus; just enable it.
 
- [ ] `controller.metrics.enabled: true`
- [ ] `controller.metrics.serviceMonitor.enabled: true`
- [ ] `controller.metrics.serviceMonitor.additionalLabels.release: <stack-release-name>`
- [ ] Confirm `ingress-nginx` target UP
 
**DoD:** target UP; `nginx_ingress_controller_requests` returns data.
EOF
)" "prometheus,servicemonitor" "M3 - Scrape Nginx Ingress"
 
# --- M4 -------------------------------------------------------------------
create_issue "Scrape MySQL (exporter via chart)" \
"$(cat <<'EOF'
Pattern: **sidecar exporter** — MySQL needs mysqld-exporter; the Bitnami chart bundles it.
 
- [ ] `metrics.enabled: true`
- [ ] `metrics.serviceMonitor.enabled: true`
- [ ] `metrics.serviceMonitor.labels.release: <stack-release-name>`
- [ ] Confirm `mysql` target UP
 
**DoD:** target UP; `mysql_up` returns 1.
EOF
)" "prometheus,exporter,servicemonitor" "M4 - Scrape MySQL"
 
# --- M5 -------------------------------------------------------------------
create_issue "Scrape Java app (custom port 8081)" \
"$(cat <<'EOF'
Pattern: **native on a non-standard port/path** — no exporter, hand-write the ServiceMonitor.
 
- [ ] Expose port 8081 on the Java Service (named `metrics` port)
- [ ] Find the real metrics path (e.g. `/actuator/prometheus`)
- [ ] Write a ServiceMonitor: port `metrics`, that path, `release` label set
- [ ] Confirm `java-app` target UP
 
**DoD:** target UP; `jvm_memory_used_bytes` returns data.
**Gotcha:** defaults assume `/metrics` on the app port — they won't find 8081. Must be explicit.
EOF
)" "prometheus,servicemonitor" "M5 - Scrape Java app"
 
# --- M6 -------------------------------------------------------------------
create_issue "Verify all targets in Prometheus UI" \
"$(cat <<'EOF'
- [ ] Status -> Targets: nginx, mysql, java all UP, no scrape errors
- [ ] One PromQL query per service returns data
- [ ] (Optional) browse bundled Grafana dashboards
 
**DoD:** three custom targets UP alongside defaults; live data returned.
EOF
)" "verify" "M6 - Verify in Prometheus UI"
 
# --- M7 -------------------------------------------------------------------
create_issue "Docs, reproducibility & STAR summary" \
"$(cat <<'EOF'
- [ ] README: architecture, the 3 scraping patterns, run + teardown
- [ ] Full reproducibility: destroy -> apply -> site.yml -> all targets UP
- [ ] STAR-method interview summary
 
**DoD:** a stranger can clone, run, and see monitoring working from the README.
EOF
)" "docs" "M7 - Polish & alerting"
 
create_issue "Proactive alerting (stretch)" \
"$(cat <<'EOF'
The real point of the scenario — turn visibility into proactive alerts.
 
- [ ] PrometheusRule: MySQL down
- [ ] PrometheusRule: Ingress 5xx rate high
- [ ] PrometheusRule: Java app target down
- [ ] Wire to Alertmanager (and a receiver)
- [ ] (Optional) custom Grafana dashboard for the app
 
**DoD:** killing a pod fires an alert before any user would notice.
EOF
)" "prometheus,stretch" "M7 - Polish & alerting"
 
echo ">> Done. Open: https://github.com/$REPO/issues"
 
