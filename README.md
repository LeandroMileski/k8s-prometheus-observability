# k8s-prometheus-observability

Know about problems before your customers do.

This project adds a full Prometheus observability stack on top of a Kubernetes-hosted Java + MySQL + Nginx Ingress application. Instead of reacting to customer complaints, you get alerted the moment something breaks — before anyone notices.

---

## What this project does

- Scrapes metrics from three targets: Nginx Ingress Controller, MySQL, and a Spring Boot Java app
- Evaluates alert rules for high error rates, database issues, and replica mismatches
- Routes alerts to email via Alertmanager when conditions are met
- Visualises the full stack health in a custom Grafana dashboard

---

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │           Kubernetes Cluster         │
                        │                                      │
  Browser ──► Nginx Ingress Controller ──► Java App (x3)      │
                   │                            │              │
                   │                        MySQL HA           │
                   │                      (primary + 2x secondary)
                   │                                           │
                   │         ┌────────────────────────────┐   │
                   │         │     monitoring namespace    │   │
                   └────────►│  Prometheus Operator Stack  │   │
                             │  - Prometheus               │   │
                             │  - Alertmanager             │   │
                             │  - Grafana                  │   │
                             │  - kube-state-metrics       │   │
                             │  - node-exporter            │   │
                             └────────────┬───────────────┘   │
                                          │                    │
                        └─────────────────│────────────────────┘
                                          │
                                          ▼
                                    Email (SendGrid)
```

---

## The three scraping patterns

Every scraping task is the same shape: make metrics reachable, then create a ServiceMonitor the Operator will select. The variable is whether the app speaks Prometheus natively or needs an exporter.

### 1. Native metrics — Nginx Ingress Controller

ingress-nginx exposes a Prometheus endpoint natively. Enable it via Helm values and point a ServiceMonitor at it — no extra processes needed.

```yaml
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: kube-prometheus-stack
```

### 2. Sidecar exporter — MySQL

MySQL has no built-in Prometheus endpoint. The Bitnami chart bundles `mysqld-exporter` which connects to MySQL, queries its internal stats, and exposes them in Prometheus format. Enable it via Helm values.

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack
```

### 3. Native on custom port/path — Java app (Spring Boot)

The Java app exposes metrics natively via Micrometer + Actuator, but on a non-standard port (8081) and path (/actuator/prometheus). The Service must expose port 8081 and the ServiceMonitor must specify both explicitly — defaults won't find it.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: java-app
  labels:
    release: kube-prometheus-stack
spec:
  endpoints:
    - port: metrics
      path: /actuator/prometheus
```

**The #1 gotcha:** the `release` label must match your kube-prometheus-stack release name exactly. A wrong or missing label means the Operator silently ignores the ServiceMonitor — the target never appears, no error, no warning.

---

## Alert rules

| Alert | Condition | Severity |
|---|---|---|
| NginxHighErrorRate | >5% of requests returning 4xx | warning |
| MySQLDown | mysql_up == 0 | critical |
| MySQLTooManyConnections | connections > 100 | warning |
| JavaTooManyRequests | request rate > 10 req/s | warning |
| StatefulSetReplicasMismatch | ready replicas != desired replicas | critical |

Alerts route to email via Alertmanager → SendGrid.

---

## Stack

| Component | Technology |
|---|---|
| Infra provisioning | Terraform (Linode) |
| Configuration management | Ansible |
| Kubernetes | kubeadm, v1.32 |
| Monitoring | kube-prometheus-stack (Prometheus Operator) |
| Ingress | Nginx Ingress Controller |
| Database | MySQL via Bitnami Helm chart (HA replication) |
| App | Spring Boot (Java 21) |
| Alerting | Alertmanager → SendGrid → Email |

---

## Prerequisites

- Terraform installed
- Ansible installed with `kubernetes.core` collection:
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml
  ```
- `gh` CLI authenticated
- Linode API token
- SendGrid account with a verified Sender Identity
- Ansible Vault password file at `~/.vault_pass`

---

## Setup

### 1. Terraform variables

Copy the example and fill in your values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

```hcl
# terraform/terraform.tfvars
ssh_pubkey   = "ssh-rsa ..."
region       = "us-ord"
worker_count = 1
linode_token = "your-linode-token"
root_pass_comp = "password-complement"
```

### 2. Ansible Vault

Create the vault file:

```bash
ansible-vault create ansible/group_vars/all/vault.yml
```

Populate it using this structure (see `vault.yml.example` for reference):

```yaml
# Database credentials
db_user: "appuser"
db_password: "your-db-password"
db_root_password: "your-db-root-password"

# SendGrid API Key — used by Alertmanager to send alert emails
vault_sendgrid_api_key: "your-sendgrid-api-key"
```

> **SendGrid setup:** create a free account at sendgrid.com, generate an API key with "Mail Send" permission, and verify your sender email address under Settings → Sender Authentication.

Save your vault password to `~/.vault_pass` and restrict permissions:

```bash
echo "your-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

---

## Deploy

A single script provisions the infrastructure, waits for all VMs to accept SSH, and runs the full Ansible stack:

```bash
./deploy.sh
```

The script handles everything in order:
1. `terraform apply` — provisions Linode VMs, firewall, and generates the Ansible inventory
2. Waits for all nodes to accept SSH connections before proceeding
3. `ansible-playbook playbooks/site.yml` — deploys the full stack

`site.yml` runs the playbooks in this order:

1. `00-bootstrap-cluster.yml` — kubeadm cluster + storage
2. `04-monitoring.yml` — Prometheus Operator stack + CRDs (must come before ingress and MySQL so ServiceMonitor CRDs exist)
3. `01-ingress.yml` — Nginx Ingress Controller + ServiceMonitor
4. `02-mysql-ha.yml` — replicated MySQL + ServiceMonitor
5. `03-deploy-app.yml` — Java application + Ingress rule

> **Why monitoring deploys before the app stack?** The Prometheus Operator installs the `ServiceMonitor` and `PrometheusRule` CRDs. Ingress and MySQL both create ServiceMonitors during their Helm install — if the CRDs don't exist yet, those installs fail.

---

## Verify

```bash
# Check all pods Running
kubectl get pods -A

# Check all three custom targets have ServiceMonitors
kubectl get servicemonitor -A

# Check alert rules loaded
kubectl get prometheusrule -A
```

Access the UIs (get NodePorts with `kubectl get svc -A`):

| UI | Default NodePort |
|---|---|
| Prometheus | 30090 |
| Grafana | 30148 (admin / prom-operator) |
| Alertmanager | 30903 |

Import `grafana/k8s-observability-dashboard.json` into Grafana to load the custom dashboard.

---

## Teardown

```bash
./destroy.sh
```

---

## Lessons learned

**The Operator pattern changes how you think about config.** You never edit a `prometheus.yml`. Instead you create Kubernetes resources — ServiceMonitor, PrometheusRule — and the Operator rewrites Prometheus config automatically. The mental shift from "edit a file" to "create a CRD" is the core concept.

**Scraping metrics is visibility. Alert rules make it proactive.** A target showing UP in Prometheus means you can see what's happening. A PrometheusRule firing before a user complains is the actual goal.

**Real troubleshooting happens at the network layer.** Linode's firewall was rejecting intra-cluster connections, causing the Nginx admission webhook to fail on deployment. Debugging this required tracing from pod events → webhook calls → firewall rules — a reminder that Kubernetes problems are often infrastructure problems in disguise.