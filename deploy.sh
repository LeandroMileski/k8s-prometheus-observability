#!/usr/bin/env bash
# deploy.sh — provision infra and deploy full stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Terraform apply"
cd "$SCRIPT_DIR/terraform"
terraform init -input=false
terraform apply -auto-approve

echo ">> Collecting node IPs"
CP_IP=$(terraform output -raw control_plane_ip)
WORKER_IPS=$(terraform output -json worker_ips | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin)))")

ALL_IPS="$CP_IP $WORKER_IPS"

echo ">> Waiting for VMs to accept SSH..."
for HOST in $ALL_IPS; do
  echo "   Waiting for $HOST..."
  until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@$HOST "echo ok" 2>/dev/null; do
    sleep 5
  done
  echo "   $HOST is ready"
done

echo ">> Running Ansible"
cd "$SCRIPT_DIR/ansible"
ansible-playbook playbooks/site.yml

echo ">> Done. Stack is up."