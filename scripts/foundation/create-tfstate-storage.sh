#!/usr/bin/env bash
#
# Terraform State Storage Account Creation Script
# ==============================================
#
# This script creates the Azure Storage Account that will hold Terraform state
# for all your landing zone modules. This is kept separate from Terraform-managed
# infrastructure to avoid circular dependencies.
#
# USAGE:
# ------
#   ./scripts/foundation/create-tfstate-storage.sh \
#     --subscription-id "your-sub-id" \
#     --resource-group "rg-tfstate" \
#     --storage-account "sttfstateunique" \
#     --location "westeurope" \
#     --container "tfstate"
#
# OPTIONAL SECURITY FLAGS:
# ------------------------
#   --disable-public-access     # Disable public network access (recommended)
#   --allow-current-ip          # Add your current IP to firewall rules
#   --enable-soft-delete        # Enable blob soft delete (recommended)
#   --retention-days 30         # Soft delete retention period
#
# EXAMPLES:
# ---------
# Basic usage:
#   ./create-tfstate-storage.sh --subscription-id "abc-123" --resource-group "rg-tfstate" --storage-account "sttfstate001"
#
# Secure setup:
#   ./create-tfstate-storage.sh \
#     --subscription-id "abc-123" \
#     --resource-group "rg-tfstate" \
#     --storage-account "sttfstate001" \
#     --disable-public-access \
#     --allow-current-ip \
#     --enable-soft-delete

set -euo pipefail

# Default values
LOCATION="westeurope"
CONTAINER_NAME="tfstate"
ENABLE_SOFT_DELETE=false
RETENTION_DAYS=30
DISABLE_PUBLIC_ACCESS=false
ALLOW_CURRENT_IP=false
VERBOSE=false

# Required parameters
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
STORAGE_ACCOUNT=""

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

verbose() {
    [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

warn() {
    echo "[WARN] $*" >&2
}

# Help function
show_help() {
    cat << EOF
Terraform State Storage Account Creation Script

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    --subscription-id ID        Azure subscription ID
    --resource-group NAME       Resource group name (will be created if needed)
    --storage-account NAME      Storage account name (must be globally unique)

OPTIONAL OPTIONS:
    --location LOCATION         Azure region (default: westeurope)
    --container NAME            Container name (default: tfstate)
    --disable-public-access     Disable public network access
    --allow-current-ip          Add current public IP to storage firewall
    --enable-soft-delete        Enable blob soft delete protection
    --retention-days DAYS       Soft delete retention period (default: 30)
    --verbose                   Enable verbose logging
    --help                      Show this help message

EXAMPLES:
    # Basic setup
    $0 --subscription-id "abc-123" --resource-group "rg-tfstate" --storage-account "sttfstate001"
    
    # Secure setup with network restrictions
    $0 --subscription-id "abc-123" \\
       --resource-group "rg-tfstate" \\
       --storage-account "sttfstate001" \\
       --disable-public-access \\
       --allow-current-ip \\
       --enable-soft-delete

NOTE: Storage account names must be globally unique and 3-24 characters (lowercase letters and numbers only).
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subscription-id)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --disable-public-access)
                DISABLE_PUBLIC_ACCESS=true
                shift
                ;;
            --allow-current-ip)
                ALLOW_CURRENT_IP=true
                shift
                ;;
            --enable-soft-delete)
                ENABLE_SOFT_DELETE=true
                shift
                ;;
            --retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Validate parameters
validate_params() {
    local errors=0
    
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Missing required parameter: --subscription-id"
        ((errors++))
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Missing required parameter: --resource-group"
        ((errors++))
    fi
    
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        error "Missing required parameter: --storage-account"
        ((errors++))
    fi
    
    # Validate storage account name
    if [[ ! "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
        error "Storage account name must be 3-24 characters, lowercase letters and numbers only: $STORAGE_ACCOUNT"
        ((errors++))
    fi
    
    # Validate retention days
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$RETENTION_DAYS" -lt 1 ]] || [[ "$RETENTION_DAYS" -gt 365 ]]; then
        error "Retention days must be between 1 and 365: $RETENTION_DAYS"
        ((errors++))
    fi
    
    [[ $errors -gt 0 ]] && exit 1
}

# Check prerequisites
check_prerequisites() {
    verbose "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az >/dev/null 2>&1; then
        error "Azure CLI (az) is required but not installed"
    fi
    
    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        error "Please log in to Azure CLI first: az login"
    fi
    
    verbose "Prerequisites check passed"
}

# Get current public IP
get_current_ip() {
    local ip=""
    for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(curl -fsS "$url" 2>/dev/null | tr -d '\r\n' || true)
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break || ip=""
    done
    echo "$ip"
}

# Create or verify resource group
create_resource_group() {
    log "Checking resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Resource group already exists: $RESOURCE_GROUP"
    else
        log "Creating resource group: $RESOURCE_GROUP in $LOCATION"
        if ! az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null; then
            error "Failed to create resource group: $RESOURCE_GROUP"
        fi
        log "Resource group created successfully"
    fi
}

# Create storage account
create_storage_account() {
    log "Checking storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "Storage account already exists: $STORAGE_ACCOUNT"
        return 0
    fi
    
    log "Creating storage account: $STORAGE_ACCOUNT"
    verbose "Location: $LOCATION, SKU: Standard_LRS, Kind: StorageV2"
    
    if ! az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --encryption-services blob \
        --https-only true \
        --min-tls-version TLS1_2 >/dev/null; then
        error "Failed to create storage account: $STORAGE_ACCOUNT"
    fi
    
    log "Storage account created successfully"
}

# Configure storage account security
configure_storage_security() {
    log "Configuring storage account security..."
    
    # Enable versioning
    verbose "Enabling blob versioning"
    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-versioning true >/dev/null
    
    # Configure soft delete if requested
    if [[ "$ENABLE_SOFT_DELETE" == "true" ]]; then
        verbose "Enabling soft delete with $RETENTION_DAYS days retention"
        az storage account blob-service-properties update \
            --account-name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --delete-retention-days "$RETENTION_DAYS" \
            --enable-delete-retention true >/dev/null
        log "Soft delete enabled with $RETENTION_DAYS days retention"
    fi
    
    # Configure network access
    if [[ "$DISABLE_PUBLIC_ACCESS" == "true" ]]; then
        verbose "Disabling public network access"
        az storage account update \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --public-network-access Disabled >/dev/null
        
        if [[ "$ALLOW_CURRENT_IP" == "true" ]]; then
            warn "Cannot add IP rules when public access is disabled. Enable public access first, add IP rules, then disable."
        fi
        
        log "Public network access disabled"
    elif [[ "$ALLOW_CURRENT_IP" == "true" ]]; then
        local current_ip
        current_ip=$(get_current_ip)
        
        if [[ -n "$current_ip" ]]; then
            verbose "Adding current IP to firewall: $current_ip"
            az storage account network-rule add \
                --account-name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --ip-address "$current_ip" >/dev/null
            log "Added current IP to storage firewall: $current_ip"
        else
            warn "Could not determine current public IP address"
        fi
    fi
}

# Create container
create_container() {
    log "Creating container: $CONTAINER_NAME"
    
    # Check if container exists
    if az storage container show \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" >/dev/null 2>&1; then
        log "Container already exists: $CONTAINER_NAME"
        return 0
    fi
    
    # Create container
    if ! az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --public-access off >/dev/null; then
        error "Failed to create container: $CONTAINER_NAME"
    fi
    
    log "Container created successfully: $CONTAINER_NAME"
}

# Display configuration summary
show_summary() {
    cat << EOF

=== Terraform State Storage Configuration ===
Subscription ID:    $SUBSCRIPTION_ID
Resource Group:     $RESOURCE_GROUP
Storage Account:    $STORAGE_ACCOUNT
Location:           $LOCATION
Container:          $CONTAINER_NAME
Public Access:      $([ "$DISABLE_PUBLIC_ACCESS" == "true" ] && echo "Disabled" || echo "Enabled")
Soft Delete:        $([ "$ENABLE_SOFT_DELETE" == "true" ] && echo "Enabled ($RETENTION_DAYS days)" || echo "Disabled")
Current IP Added:   $([ "$ALLOW_CURRENT_IP" == "true" ] && echo "Yes" || echo "No")

=== Terraform Backend Configuration ===
Add this to your Terraform configuration files:

terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"  # Or module-specific name
  }
}

=== Next Steps ===
1. Update your configs/bootstrap.yaml with these values:
   tfstate:
     subscription_id: "$SUBSCRIPTION_ID"
     resource_group: "$RESOURCE_GROUP"
     storage_account: "$STORAGE_ACCOUNT"
     container: "$CONTAINER_NAME"

2. Initialize your Terraform configurations:
   cd stacks/bootstrap
   terraform init

3. Deploy your bootstrap infrastructure:
   terraform plan
   terraform apply

==============================================

EOF
}

# Main execution
main() {
    log "Starting Terraform state storage setup..."
    
    parse_args "$@"
    validate_params
    check_prerequisites
    
    # Set the subscription
    log "Setting Azure subscription: $SUBSCRIPTION_ID"
    if ! az account set --subscription "$SUBSCRIPTION_ID"; then
        error "Failed to set subscription: $SUBSCRIPTION_ID"
    fi
    
    # Execute setup steps
    create_resource_group
    create_storage_account
    configure_storage_security
    create_container
    
    log "Terraform state storage setup completed successfully!"
    show_summary
}

# Run main function with all arguments
main "$@"