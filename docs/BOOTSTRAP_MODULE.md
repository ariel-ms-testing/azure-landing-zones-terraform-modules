# Bootstrap Module Documentation

The Bootstrap module creates the foundational authentication and deployment infrastructure for Azure Landing Zones. This module establishes the security framework and automation capabilities required for subsequent infrastructure deployments.

## Purpose and Capabilities

The Bootstrap module serves as the cornerstone of the entire Infrastructure-as-Code solution by creating:

### Authentication Infrastructure
- **Azure AD Applications**: Service principals for each module type or environment
- **Federated Credentials**: OIDC integration with GitHub Actions eliminating secret management
- **Service Principal Permissions**: Least privilege access with appropriate RBAC assignments
- **Cross-Subscription Access**: Automated permission setup for multi-subscription deployments

### Deployment Automation
- **GitHub Environments**: Automated creation of deployment environments
- **Environment Protection**: Manual approval gates and access controls
- **Secret Management**: Automated injection of Azure credentials into GitHub
- **Workflow Integration**: Seamless integration with GitHub Actions workflows

### Security Framework
- **Key Vault Integration**: Secure storage for sensitive configuration data
- **Network Access Controls**: IP restrictions and subnet-based access
- **Audit Logging**: Comprehensive logging of authentication and access events
- **Compliance Support**: Framework for regulatory and governance requirements

## Module Architecture

```
Bootstrap Module
├── Authentication
│   ├── Azure AD Applications
│   ├── Service Principals
│   ├── Federated Credentials
│   └── RBAC Assignments
├── GitHub Integration
│   ├── Environment Creation
│   ├── Secret Management
│   ├── Protection Rules
│   └── Access Controls
├── Security Infrastructure
│   ├── Key Vault
│   ├── Network Access
│   ├── Purge Protection
│   └── Audit Configuration
└── Backend Configuration
    ├── State Storage
    ├── Backend Generation
    ├── Lock Management
    └── Access Permissions
```

## Configuration Schema

The Bootstrap module uses a YAML configuration file with the following structure:

### Required Settings
```yaml
tenant_id: "azure-tenant-id"
github:
  owner: "github-organization"
  repo: "repository-name"
```

### Bootstrap Configuration
```yaml
bootstrap:
  github_enabled: true/false           # Enable GitHub Actions integration
  github:
    use_single_sp: true/false          # Single SP vs module-scoped SPs
    use_module_scoped_sp: true/false   # Module-specific service principals
    use_federated_credentials: true/false # OIDC vs client secrets
  key_vault:
    name: "globally-unique-name"
    allowed_ips: ["ip-ranges"]
    allowed_subnets: ["subnet-ids"]
    purge_protection: true/false
```

### Module Enablement
```yaml
modules:
  network:
    enabled: true/false
  mg:
    enabled: true/false
    environment: "environment-name"
    scope_id: "management-group-id"
    managed_subscriptions: ["subscription-ids"]
  policy:
    enabled: true/false
    environment: "environment-name"
    scope_id: "management-group-id"
```

## Service Principal Strategy

The module supports three service principal strategies:

### Single Service Principal
- **Use Case**: Simple deployments with unified permissions
- **Configuration**: `use_single_sp: true`
- **Permissions**: Broad access across all modules and environments
- **Security Trade-off**: Simpler management but broader attack surface

### Environment-Scoped Service Principals
- **Use Case**: Environment isolation (hub-westeurope, spoke1, etc.)
- **Configuration**: `use_single_sp: false, use_module_scoped_sp: false`
- **Permissions**: Scoped to specific environments
- **Security Benefit**: Environment isolation with targeted access

### Module-Scoped Service Principals (Recommended)
- **Use Case**: Module-specific permissions with least privilege
- **Configuration**: `use_module_scoped_sp: true`
- **Permissions**: Dedicated SPs for mg, network, and policy modules
- **Security Benefit**: Minimal required permissions per module type

## Authentication Methods

### OIDC Federated Credentials (Recommended)
- **Security**: No secrets stored in GitHub
- **Maintenance**: No secret rotation required
- **Integration**: Native GitHub Actions OIDC support
- **Limitation**: Requires GitHub Actions environment

### Client Secrets
- **Compatibility**: Works with any CI/CD system
- **Maintenance**: Requires periodic secret rotation
- **Security**: Secrets stored in GitHub (encrypted)
- **Use Case**: Legacy systems or non-GitHub environments

## Key Vault Configuration

### Security Features
- **Network Access Controls**: IP and subnet restrictions
- **Purge Protection**: Prevents accidental deletion in production
- **Soft Delete**: Recovery capability for deleted secrets
- **RBAC Integration**: Role-based access control instead of access policies

## Deployment Process

### Prerequisites
The Bootstrap module requires high-privilege access:
- **Azure AD Permissions**: Global Administrator or Application Administrator
- **Azure RBAC**: Owner or User Access Administrator on target subscriptions
- **GitHub Permissions**: Repository admin access for environment creation

### Deployment Steps
1. **External State Storage**: Create Terraform backend storage account
2. **Configuration**: Customize bootstrap-example.yaml for your organization
3. **Local Deployment**: Run bootstrap locally with admin credentials
4. **Validation**: Verify service principals, environments, and permissions
5. **Testing**: Validate GitHub Actions integration with test deployment

### Post-Deployment
- **Service Principal Validation**: Confirm correct permissions and scope
- **GitHub Environment Testing**: Verify environment protection and secrets
- **Key Vault Access**: Test network access controls and RBAC permissions
- **Workflow Integration**: Execute test runs of dependent modules

## Troubleshooting

### Common Issues
- **Permission Errors**: Verify admin privileges and tenant access
- **GitHub Integration**: Check repository permissions and organization settings
- **Key Vault Access**: Validate network access rules and IP restrictions
- **Service Principal Creation**: Confirm Azure AD application registration permissions

### Validation Commands
```bash
# Check Azure AD applications
az ad app list --display-name "app-name"

# Verify service principal permissions
az role assignment list --assignee "service-principal-id"

# Test Key Vault access
az keyvault secret list --vault-name "vault-name"

# Validate GitHub environments
gh api repos/owner/repo/environments
```

## Integration with Other Modules

### Management Groups Module
- **Dependencies**: Service principal with Management Group Contributor role
- **Authentication**: Uses bootstrap-created credentials for deployment
- **Scope**: Operates within management group scope defined in bootstrap

### Network Module
- **Dependencies**: Service principal with Network Contributor role
- **Multi-Subscription**: Leverages cross-subscription permissions from bootstrap