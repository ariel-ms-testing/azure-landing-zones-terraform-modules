# Network Module Documentation

The Network module implements hub-spoke network architecture for Azure Landing Zones with multi-subscription support, centralized security, and automated connectivity management. This module provides enterprise-grade networking with flexibility for various organizational requirements.

## Purpose and Capabilities

The Network module delivers comprehensive networking solutions through:

### Hub-Spoke Architecture
- **Centralized Connectivity**: Hub networks provide shared services and connectivity
- **Workload Isolation**: Spoke networks isolate workloads while maintaining connectivity
- **Scalable Design**: Support for multiple hubs and unlimited spokes
- **Cross-Subscription Deployment**: Seamless networking across subscription boundaries

### Security Integration
- **Azure Firewall**: Centralized network security with policy management
- **NAT Gateway Integration**: Optimized outbound connectivity with dedicated public IPs
- **Route Management**: Automated User Defined Routes for traffic steering
- **Network Segmentation**: Subnet-level isolation with service endpoint support

### Connectivity Automation
- **Automated Peering**: Hub-to-spoke VNet peering with proper configuration
- **Cross-Subscription Support**: Remote state integration for resource references
- **Routing Automation**: Dynamic route table creation and association

## Module Architecture

```
Network Module
├── Foundation (VNet Deployment)
│   ├── Hub Virtual Networks
│   ├── Spoke Virtual Networks
│   ├── Subnet Configuration
│   └── Service Endpoints
├── Security (Centralized Protection)
│   ├── Azure Firewall
│   ├── Firewall Policies
│   ├── NAT Gateway
│   └── Network Security Groups
├── Connectivity (Inter-Network Communication)
│   ├── VNet Peering
│   ├── Route Tables
│   ├── User Defined Routes
│   └── DNS Configuration
└── Cross-Subscription Integration
    ├── Remote State Access
    ├── Azure CLI Provisioners
    ├── Resource References
    └── Permission Management
```

## Hub Network Design

### Core Components
```yaml
hubs:
  - name: "hub-westeurope"
    subscription_id: "hub-subscription-id"
    vnet:
      address_space: ["10.0.0.0/16"]
      subnets:
        - name: "AzureFirewallSubnet"      # Required for Azure Firewall
          address_prefixes: ["10.0.0.0/26"]
        - name: "GatewaySubnet"            # Optional for VPN/ExpressRoute
          address_prefixes: ["10.0.1.0/27"]
        - name: "snet-shared-services"     # Shared infrastructure
          address_prefixes: ["10.0.2.0/24"]
```

### Azure Firewall Configuration
```yaml
firewall:
  enabled: true
  sku_tier: "Standard"                   # Standard | Premium
  outbound_method: "nat_gateway"         # firewall | nat_gateway
  
  nat_gateway:
    public_ip_count: 1                   # 1-16 public IPs
    idle_timeout_minutes: 4              # 4-120 minutes
    zones: ["1", "2", "3"]               # Availability zones
  
  policy:
    threat_intel_mode: "Alert"           # Off | Alert | Deny
    dns_proxy_enabled: true              # DNS proxy through firewall
    private_ranges: ["IANAPrivateRanges"]
```

## Spoke Network Design

### Network Configuration
```yaml
spokes:
  - name: "spoke-production"
    subscription_id: "prod-subscription-id"
    vnet:
      address_space: ["10.1.0.0/16"]
      subnets:
        - name: "snet-web"
          address_prefixes: ["10.1.1.0/24"]
          route_to_firewall: true
          service_endpoints: ["Microsoft.Storage"]
```

### Connectivity Settings
```yaml
connectivity:
  hub_name: "hub-westeurope"             # Target hub for peering
  enable_peering: true                   # Enable VNet peering
  allow_forwarded_traffic: true         # Allow hub-forwarded traffic
  use_remote_gateways: false             # Use hub VPN/ExpressRoute gateways
```

## Multi-Subscription Architecture

### Cross-Subscription Challenges
- **Resource References**: Accessing resources across subscription boundaries
- **Authentication**: Service principal permissions across subscriptions
- **State Management**: Terraform state isolation and sharing
- **Networking**: VNet peering across different subscriptions

### Solution Implementation
```terraform
# Remote State Data Source
data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tf_backend_config.resource_group
    storage_account_name = var.tf_backend_config.storage_account
    container_name       = var.tf_backend_config.container
    key                  = "hub-${hub_name}.tfstate"
  }
}

# Cross-Subscription Peering with Azure CLI
resource "null_resource" "spoke_to_hub_peering" {
  provisioner "local-exec" {
    command = "az network vnet peering create ..."
  }
}
```

### Remote State Integration
- **Hub State Access**: Spokes access hub network information via remote state
- **Resource ID References**: Direct access to hub firewall private IPs
- **Configuration Sharing**: Centralized network configuration distribution
- **Dependency Management**: Proper resource creation ordering

## Deployment Phases

### Phase 1: Foundation (Hubs)
```bash
# Deploy hub networks first
terraform apply -var="deployment_phase=hub"
```
- **VNet Creation**: Hub virtual networks and subnets
- **Security Services**: Azure Firewall and NAT Gateway
- **DNS Configuration**: DNS proxy and custom DNS settings
- **Monitoring Setup**: Diagnostic logging and metrics

### Phase 2: Connectivity (Spokes)
```bash
# Deploy spoke networks and connectivity
terraform apply -var="deployment_phase=spoke"
```
- **Spoke VNets**: Spoke virtual networks and subnets
- **Peering Creation**: Hub-to-spoke VNet peering
- **Route Configuration**: User Defined Routes through firewall
- **Network Integration**: Service endpoints and private endpoints

### Phase 3: Optimization
- **Performance Tuning**: Bandwidth and latency optimization
- **Security Hardening**: Network security group rule refinement
- **Monitoring Enhancement**: Advanced network monitoring setup
- **Backup Configuration**: Network configuration backup and recovery

## Security Architecture

### Centralized Security Model
```
Internet ──▶ NAT Gateway ──▶ Azure Firewall ──▶ Hub VNet
                                    │
                                    ▼
                            ┌──────────────┐
                            │ Spoke VNets  │
                            │ • Production │
                            │ • Development│
                            │ • Staging    │
                            └──────────────┘
```

## Advanced Configurations

### Multi-Region Deployment
```yaml
hubs:
  - name: "hub-westeurope"
    location: "westeurope"
    address_space: ["10.0.0.0/16"]
  
  - name: "hub-eastus"
    location: "eastus"
    address_space: ["10.10.0.0/16"]
```

## Operational Management

### Monitoring and Diagnostics
```yaml
global:
  enable_diagnostics: true
  log_analytics_workspace_id: "/subscriptions/.../workspaces/workspace"
```

## Troubleshooting

### Common Issues
- **Peering Failures**: Cross-subscription authentication problems
- **Routing Problems**: Incorrect route table configurations
- **Firewall Connectivity**: Security rule misconfigurations
- **DNS Resolution**: DNS proxy and custom DNS issues

### Diagnostic Commands
```bash
# Check VNet peering status
az network vnet peering list --resource-group rg-name --vnet-name vnet-name

# Validate route tables
az network route-table route list --resource-group rg-name --route-table-name rt-name

# Test firewall connectivity
az network firewall show --resource-group rg-name --name firewall-name

# Verify DNS configuration
nslookup domain-name firewall-private-ip
```

## Best Practices

### Network Design
- **Address Planning**: Avoid overlapping address spaces across all networks
- **Subnet Sizing**: Plan for growth and avoid frequent subnet modifications
- **Security Zoning**: Design subnets based on security requirements
- **Performance Optimization**: Consider proximity and bandwidth requirements

### Security Hardening
- **Principle of Least Privilege**: Minimal required firewall rules
- **Regular Updates**: Keep firewall policies current with security requirements
- **Monitoring**: Implement comprehensive network monitoring and alerting
- **Incident Response**: Prepare procedures for security incident handling
