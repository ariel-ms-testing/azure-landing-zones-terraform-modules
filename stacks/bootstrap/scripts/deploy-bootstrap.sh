#!/bin/bash
set -e

# Bootstrap deployment script with parameter support
# Usage: ./deploy-bootstrap.sh [backend|init|plan|apply|all]

ACTION=${1:-all}

case $ACTION in
    "backend")
        echo " Generating backend configuration..."
        python3 scripts/generate-backend.py
        ;;
    "init")
        echo " Initializing Terraform..."
        terraform init -backend-config=backend.hcl
        ;;
    "validate")
        echo " Validating Terraform configuration..."
        terraform validate
        ;;
    "plan")
        echo " Planning deployment..."
        terraform plan -out=bootstrap.tfplan
        ;;
    "apply")
        echo " Applying deployment..."
        terraform apply bootstrap.tfplan
        ;;
    "all")
        echo "Generating backend configuration..."
        python3 scripts/generate-backend.py
        echo " Initializing Terraform..."
        terraform init -backend-config=backend.hcl
        echo " Planning deployment..."
        terraform plan -out=bootstrap.tfplan
        echo " Applying deployment..."
        terraform apply bootstrap.tfplan
        ;;
    *)
        echo "Usage: $0 [backend|init|validate|plan|apply|all]"
        echo "  backend   - Generate backend.hcl from bootstrap.yaml"
        echo "  init      - Initialize Terraform with backend"
        echo "  validate  - Validate Terraform configuration"
        echo "  plan      - Plan Terraform deployment"
        echo "  apply     - Apply Terraform plan"
        echo "  all       - Run all steps (default)"
        exit 1
        ;;
esac