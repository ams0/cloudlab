#!/bin/bash
set -e

echo "=== Deploying Infrastructure ==="

# Change to terraform directory
cd terraform

# Apply terraform
echo "→ Running terraform apply..."
terraform apply -auto-approve

# Go back to root
cd ..

# Wait for SSH to be available
echo "→ Waiting for SSH to be available..."
INSTANCE_IP=$(terraform -chdir=terraform output -raw instance_public_ip)
echo "   Instance IP: $INSTANCE_IP"

MAX_RETRIES=30
RETRY_COUNT=0
while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$INSTANCE_IP exit 2>/dev/null; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "✗ SSH connection timeout after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "   Waiting for SSH... (attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 10
done

echo "✓ SSH is available"

# Run ansible
echo "→ Running ansible-playbook..."
ansible-playbook -i inventory.ini site.yml

echo "=== Deployment Complete ==="
echo "Instance IP: $INSTANCE_IP"
