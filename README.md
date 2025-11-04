
# Azure Landing Zones Terraform Modules

A modern, flexible Infrastructure-as-Code solution for Azure Landing Zones that replaces Microsoft's complex and rigid Azure Landing Zones modules with a streamlined, customizable Terraform implementation.

## Overview

This repository provides a complete Azure Landing Zones implementation with modular Terraform code, automated GitHub Actions workflows, and production-ready configurations. The solution is designed to be flexible, maintainable, and enterprise-ready while significantly reducing complexity compared to Microsoft's official modules.

## Key Differentiators

### Flexibility Over Rigidity
- **Complete customization freedom** for organizational hierarchies and network architectures
- **Modular design** allowing selective deployment of components
- **Configuration-driven** approach with YAML files instead of complex HCL
- **Multi-subscription support** with cross-subscription resource management

### Simplified Implementation
- **Sequential deployment automation** with proper dependency management
- **Comprehensive validation** with clear error messages and fix suggestions
- **Production-ready examples** with detailed documentation

### Enterprise-Grade Security
- **OIDC federated credentials** eliminating secret management
- **Least privilege access** with module-scoped service principals
- **Environment protection** with manual approval gates
- **Cross-subscription permissions** handled automatically

## Architecture

The solution consists of three core modules deployed in sequence:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    Bootstrap    │───▶│ Management      │───▶│    Network      │
│                 │    │ Groups          │    │                 │
│ • Azure AD Apps │    │ • Hierarchy     │    │ • Hub-Spoke     │
│ • Service       │    │ • Subscriptions │    │ • Firewalls     │
│   Principals    │    │ • Governance    │    │ • Connectivity  │
│ • GitHub Envs   │    │ • RBAC          │    │ • Routing       │
│ • OIDC Config   │    │ • Policies      │    │ • Security      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Bootstrap Module
Creates foundational authentication and deployment infrastructure:
- Azure AD applications and service principals with federated credentials
- GitHub environments with automated secret management
- Key Vault for secure storage
- RBAC role assignments with least privilege access
- Terraform backend configuration and state management

### Management Groups Module
Implements organizational hierarchy and governance:
- Flexible management group structures (up to 6 levels deep)
- Subscription assignment and movement capabilities
- Dependency validation and circular reference prevention
- Support for any organizational model or compliance framework

### Network Module
Deploys hub-spoke network architecture:
- Multi-subscription hub and spoke networks
- Azure Firewall with policy management
- NAT Gateway integration for optimized outbound connectivity
- Automated VNet peering and route table configuration
- Cross-subscription networking with remote state integration

## Repository Structure

```
├── configs/                    # Configuration files
│   ├── bootstrap-example.yaml # Bootstrap template
│   ├── mg-example.yaml       # Management groups template
│   └── network-example.yaml  # Network template
├── modules/                   # Terraform modules
│   ├── bootstrap/            # Bootstrap module
│   ├── mg/                   # Management groups module
│   └── network/              # Network module
├── stacks/                   # Deployment stacks
│   ├── bootstrap/            # Bootstrap stack
│   ├── mg/                   # Management groups stack
│   └── network/              # Network stack
├── scripts/                  # Deployment scripts
│   ├── deploy-local.sh       # Local deployment script
│   └── foundation/           # Foundation scripts
├── .github/
│   ├── workflows/            # GitHub Actions workflows
│   └── actions/              # Composite actions
└── docs/                     # Documentation
```

## Deployment Workflow

The solution uses GitHub Actions with sequential deployment phases:

1. **Bootstrap Phase**: Creates authentication infrastructure (manual deployment required)
2. **Management Groups Phase**: Deploys organizational hierarchy
3. **Network Hubs Phase**: Deploys hub networks with security services
4. **Network Spokes Phase**: Deploys spoke networks with connectivity
5. **Policy Phase**: Applies governance policies (optional)

Each phase includes:
- Terraform plan generation with change detection
- Manual approval gates for production deployments
- State management with external storage

## Key Features

### Configuration Management
- **YAML-based configuration** for all modules
- **Template files** with comprehensive documentation
- **Validation rules** preventing common configuration errors
- **Environment-specific** parameter support

### Automation
- **Composite GitHub Actions** 
- **Matrix deployments** for multi-environment scenarios
- **Conditional execution** based on change detection
- **Parallel execution** where dependencies allow

### Security
- **OIDC authentication** with no stored secrets
- **Least privilege** service principal configuration
- **Environment protection** with approval workflows

### Multi-Subscription Support
- **Cross-subscription resource management**
- **Remote state integration** for resource references
- **Automated RBAC configuration**
- **Subscription filtering** for targeted deployments

## Getting Started

### Prerequisites
- Azure CLI with Global Administrator permissions
- GitHub repository with admin access
- Terraform 1.5+ installed locally
- Understanding of Azure networking and governance concepts

### Quick Start
1. Clone this repository
2. Create external Terraform state storage using `scripts/foundation/create-tfstate-storage.sh`
3. Customize `configs/bootstrap-example.yaml` for your organization
4. Deploy bootstrap locally: `cd stacks/bootstrap && ./scripts/deploy-bootstrap.sh all`
5. Configure remaining modules using example templates
6. Deploy via GitHub Actions workflows

### Configuration Templates
- **bootstrap-example.yaml**: Complete authentication and deployment setup
- **mg-example.yaml**: Flexible organizational hierarchy examples
- **network-example.yaml**: Hub-spoke network architecture patterns

## Benefits Over Microsoft's Solution

### Simplified Complexity
- **Reduced cognitive load** with clear module separation
- **Configuration-driven** instead of code-driven customization
- **Comprehensive documentation** with practical examples
- **Streamlined deployment** process with automation

### Enhanced Flexibility
- **Any organizational structure** instead of prescribed patterns
- **Custom network topologies** beyond standard hub-spoke
- **Selective module deployment** based on requirements
- **Easy modification** without deep Terraform knowledge

This solution is designed for smalll organization and enterprise alike. use with comprehensive documentation, examples, and validation. The modular architecture allows for easy extension and customization while maintaining security and compliance standards.

For deployment guidance, see the module-specific documentation in the `docs/` directory.