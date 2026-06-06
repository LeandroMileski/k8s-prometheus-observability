#!/usr/bin/env bash
# destroy.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/terraform"
terraform destroy -auto-approve
echo ">> Cluster destroyed."