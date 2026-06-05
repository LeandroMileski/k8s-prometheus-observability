# Build Guide — k8s-prometheus-observability

Add Prometheus monitoring to the Java + MySQL + Ingress stack you built in the
Ansible exercises. Goal: know the moment MySQL, the Ingress, or the app breaks —
and pinpoint *what* broke in seconds instead of hours.

Built milestone by milestone; each ends in a verifiable state. Reuses the
Terraform + Ansible from your `Ansible-Java-MySQL-Helm-Kubernetes` repo.

Legend: 🎯 goal · ✅ definition of done · 🧠 what to understand

---

## Milestone 0 — New repo & project bootstrap
🎯 Repo created with the adapted app-stack automation in place.

- [ ] Create the `k8s-prometheus-observability` repo on GitHub
- [ ] Copy in the adapted `terraform/` and `ansible/` from the Ansible repo
- [ ] `ansible-galaxy collection install -r ansible/requirements.yml`
- [ ] README skeleton + `.gitignore` (tfstate, tfvars, hosts.ini, vault.yml)

✅ Repo clones cleanly; `terraform validate` and `ansible --version` both pass.
🧠 You're reusing proven infra automation — observability is a layer on top, not a rebuild.

---

## Milestone 1 — Deploy the base application stack (Exercise 1)
🎯 The full app running: cluster, replicated MySQL, Java, Ingress.

- [ ] 1.1 Provision the cluster (Terraform + bootstrap playbook, incl. local-path storage)
- [ ] 1.2 MySQL via Helm — `architecture: replication`, **`secondary.replicaCount: 1`** (1 primary + 1 secondary = **2 replicas**)
- [ ] 1.3 Java app — **`replicas: 3`**, `DB_HOST` → `mysql-primary`
- [ ] 1.4 Nginx Ingress Controller via Helm
- [ ] 1.5 Ingress rule routing to the Java service

✅ App loads in a browser; `kubectl get pods` shows 2 MySQL + 3 Java pods Running.
🧠 This is your exercise 7 & 8 work with two tweaks (MySQL 2 instead of 3, Java 3). Reuse, don't rewrite.

---

## Milestone 2 — Deploy Prometheus (kube-prometheus-stack)
🎯 The Prometheus Operator stack running, UI reachable.

- [ ] 2.1 Add the `prometheus-community` Helm repo
- [ ] 2.2 New Ansible role (`monitoring`) that helm-installs `kube-prometheus-stack` into a `monitoring` namespace
- [ ] 2.3 Verify pods: Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter, operator
- [ ] 2.4 Reach the Prometheus UI (port-forward or a NodePort)

✅ Prometheus UI loads; Status → Targets shows the default Kubernetes targets already UP.
🧠 The big concept: the **Operator pattern**. You don't edit a `prometheus.yml`. Prometheus is configured by **Custom Resources** — `ServiceMonitor`, `PodMonitor`, `PrometheusRule`. The operator watches those CRDs and rewrites Prometheus's config automatically. Every milestone below is "create the right ServiceMonitor."

---

## Milestone 3 — Scrape the Nginx Ingress Controller
🎯 Ingress metrics flowing into Prometheus.

- [ ] 3.1 Recognise: ingress-nginx exposes metrics **natively** — no separate exporter needed
- [ ] 3.2 Update the ingress-nginx Helm values: `controller.metrics.enabled: true` and `controller.metrics.serviceMonitor.enabled: true`
- [ ] 3.3 Set `controller.metrics.serviceMonitor.additionalLabels.release` to your kube-prometheus-stack release name (so the operator selects it)
- [ ] 3.4 Confirm the `ingress-nginx` target is UP in Prometheus

✅ Status → Targets shows the nginx controller UP; `nginx_ingress_controller_requests` returns data.
🧠 First of three scraping patterns: **native metrics**. The app already speaks Prometheus; you just turn it on and point a ServiceMonitor at it.

---

## Milestone 4 — Scrape MySQL
🎯 MySQL metrics flowing in.

- [ ] 4.1 Recognise: MySQL does **not** speak Prometheus — it needs an **exporter** (`mysqld-exporter`)
- [ ] 4.2 The Bitnami chart bundles it: set `metrics.enabled: true` and `metrics.serviceMonitor.enabled: true`
- [ ] 4.3 Set the serviceMonitor `labels.release` to match your stack
- [ ] 4.4 Confirm the `mysql` target is UP

✅ Status → Targets shows MySQL UP; `mysql_up` returns 1.
🧠 Second pattern: **sidecar exporter**. A separate process translates MySQL's internal stats into Prometheus format. The chart deploys it for you — that's the note in the exercise about checking the chart before adding your own exporter.

---

## Milestone 5 — Scrape the Java application
🎯 App metrics flowing in — the trickiest of the three.

- [ ] 5.1 Recognise: the Java app exposes metrics **natively but on a non-standard port (8081), not `/metrics`**
- [ ] 5.2 Expose port 8081 on the Java `Service` (add a named `metrics` port)
- [ ] 5.3 Find the actual metrics path the app serves (e.g. `/actuator/prometheus` for Spring Boot)
- [ ] 5.4 Write a `ServiceMonitor` targeting the `metrics` port + that path, labelled for the operator
- [ ] 5.5 Confirm the `java-app` target is UP

✅ Status → Targets shows the Java app UP; a JVM metric (e.g. `jvm_memory_used_bytes`) returns data.
🧠 Third pattern: **native metrics on a custom port/path**. No exporter, but you must hand-write the ServiceMonitor with the exact port and path — the defaults won't find it. This is why the exercise calls out 8081 specifically.

---

## Milestone 6 — Verify everything in the Prometheus UI
🎯 All three custom targets confirmed UP.

- [ ] 6.1 Status → Targets — nginx, mysql, java all UP, no scrape errors
- [ ] 6.2 Run one PromQL query per service and get data back
- [ ] 6.3 (Optional) open Grafana, log in, browse the bundled dashboards

✅ Three custom targets UP alongside the defaults; queries return live data.
🧠 "Target UP" means Prometheus successfully scraped it on the last cycle. A target DOWN here is exactly the kind of early signal that, in the scenario, would've told you about the outage before a user emailed you.

---

## Milestone 7 — Polish, portfolio & proactive alerting
🎯 Documented, reproducible, and actually proactive.

- [ ] 7.1 README: architecture, the three scraping patterns, run + teardown
- [ ] 7.2 Confirm full reproducibility: destroy → apply → site.yml → all targets UP
- [ ] 7.3 STAR-method interview summary
- [ ] 7.4 **Stretch — alerting** (the real goal of the scenario): `PrometheusRule` resources for "MySQL down", "Ingress 5xx rate high", "Java app target down", wired to Alertmanager
- [ ] 7.5 Stretch — a custom Grafana dashboard for the app

✅ A stranger could clone, run, and see monitoring working from the README.
🧠 Scraping metrics is *visibility*; alerting rules are what make it *proactive* — closing the loop on "know about issues before users do."

---

### The one idea that ties it together
Every scraping task is the same shape: **make the metrics reachable, then create a ServiceMonitor the operator will select.** The only variable is whether the app speaks Prometheus natively (nginx, java) or needs an exporter (mysql) — and the label that lets the operator find your ServiceMonitor. Get the label wrong and the target silently never appears; that's the #1 gotcha.