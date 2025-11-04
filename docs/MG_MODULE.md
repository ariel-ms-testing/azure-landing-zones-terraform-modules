# Management Groups Module Documentation

The Management Groups module implements organizational hierarchy and governance for Azure subscriptions. This module provides flexible subscription organization, policy inheritance, and access control management aligned with your organizational structure.

## Purpose and Capabilities

The Management Groups module enables enterprise-scale governance through:

### Organizational Hierarchy
- **Flexible Structure Design**: Support for any organizational model up to 6 levels deep
- **Subscription Management**: Automated subscription assignment and movement
- **Dependency Resolution**: Intelligent parent-child relationship management
- **Validation Framework**: Comprehensive error checking and prevention

### Governance Foundation
- **Policy Inheritance**: Hierarchical policy application and inheritance
- **Access Control**: Role-based access management at appropriate scopes
- **Compliance Scoping**: Organizational boundaries for regulatory requirements
- **Cost Management**: Hierarchical cost allocation and reporting

### Operational Excellence
- **Automated Deployment**: Dependency-aware resource creation
- **Configuration Validation**: Prevention of common configuration errors
- **Change Management**: Safe modification of existing hierarchies
- **Audit Support**: Comprehensive logging and change tracking

## Module Architecture

```
Management Groups Module
├── Hierarchy Management
│   ├── Depth Bucketing (Level 0-6)
│   ├── Dependency Resolution
│   ├── Parent-Child Validation
│   └── Circular Reference Prevention
├── Subscription Assignment
│   ├── Subscription Attachment
│   ├── Movement Between Groups
│   ├── Duplicate Prevention
│   └── GUID Validation
├── Validation Framework
│   ├── Schema Validation
│   ├── Hierarchy Depth Checking
│   ├── Reference Validation
│   └── Error Message Generation
└── Output Management
    ├── Resource ID Mapping
    ├── Hierarchy Visualization
    ├── Subscription Tracking
    └── Integration Points
```

## Hierarchy Design Flexibility

The module supports complete flexibility in organizational design:

### Common Patterns
```yaml
# Business Unit Structure
├── root
    ├── organization
        ├── business-unit-1
        │   ├── production
        │   └── development
        ├── business-unit-2
        │   ├── production
        │   └── development
        └── shared-services
            ├── connectivity
            ├── identity
            └── management

# Geographic Structure
├── root
    ├── organization
        ├── americas
        │   ├── north-america
        │   └── south-america
        ├── europe
        │   ├── western-europe
        │   └── eastern-europe
        └── asia-pacific
            ├── southeast-asia
            └── east-asia

# Regulatory Structure
├── root
    ├── organization
        ├── regulated
        │   ├── financial-services
        │   └── healthcare
        ├── internal
        │   ├── corporate-it
        │   └── research-development
        └── public
            ├── marketing
            └── sales
```

## Configuration Schema

### Required Elements
```yaml
schema_version: 1
management_groups:
  - id: "unique-identifier"
    display_name: "Human Readable Name"
    parent_id: "root-or-parent-id"
    subscriptions: ["subscription-guid-list"]
```

### Management Group Properties
- **id**: Unique identifier (alphanumeric, hyphens, underscores)
- **display_name**: Human-readable name displayed in Azure Portal
- **parent_id**: Either "root" or another management group's id
- **subscriptions**: Optional array of subscription GUIDs

### Validation Rules
- **Unique IDs**: Each management group ID must be unique
- **Valid Parents**: All parent_id values must reference existing groups or "root"
- **No Circular References**: Parent-child relationships cannot create loops
- **Depth Limits**: Maximum 6 levels below root management group
- **Subscription Uniqueness**: Each subscription can only belong to one group
- **GUID Format**: Subscription IDs must be valid GUIDs

## Depth Bucketing Algorithm

The module uses an intelligent depth bucketing system for dependency-safe deployment:

### Level Classification
```terraform
# Level 0: Direct children of root
level0 = { for id, mg in mg_map : id => mg if mg.parent_id == "root" }

# Level 1: Children of level 0 groups
level1 = { for id, mg in mg_map : id => mg if contains(keys(level0), mg.parent_id) }

# Continues through level 6
```

### Deployment Order
1. **Level 0**: Root-level management groups created first
2. **Level 1**: Children of level 0 groups
3. **Level 2-6**: Subsequent levels in dependency order
4. **Subscription Associations**: Applied after all groups exist

### Benefits
- **Dependency Safety**: Parents always created before children
- **Parallel Deployment**: Same-level groups can be created simultaneously
- **Error Prevention**: Impossible to create circular dependencies
- **Rollback Safety**: Deletion occurs in reverse order

## Subscription Management

### Assignment Strategies
```yaml
# Centralized Assignment (recommended for governance)
management_groups:
  - id: "production"
    display_name: "Production Workloads"
    parent_id: "workloads"
    subscriptions:
      - "prod-app1-subscription-id"
      - "prod-app2-subscription-id"

# Distributed Assignment (flexible for teams)
  - id: "team-alpha"
    display_name: "Team Alpha Resources"
    parent_id: "development"
    subscriptions:
      - "team-alpha-dev-sub-id"
      - "team-alpha-test-sub-id"
```

### Movement Capabilities
- **Safe Relocation**: Subscriptions can be moved between management groups
- **Validation**: Ensures target group exists before movement
- **Policy Inheritance**: Automatic application of new parent policies
- **Access Control**: Inherited permissions from new parent group

## Validation Framework

### Pre-Deployment Validation
```terraform
# Parent Existence Check
resource "null_resource" "parent_guard" {
  lifecycle {
    precondition {
      condition = all_parents_exist
      error_message = "Management group references non-existent parent"
    }
  }
}

# Duplicate ID Prevention
resource "null_resource" "dup_mg_id_guard" {
  lifecycle {
    precondition {
      condition = unique_ids_only
      error_message = "Duplicate management group IDs detected"
    }
  }
}
```

### Runtime Validation
- **Hierarchy Depth**: Prevents exceeding 6-level limit
- **Subscription GUID Format**: Validates subscription ID format
- **Duplicate Subscription Prevention**: Ensures single group assignment
- **Reference Integrity**: Validates all parent-child relationships

### Error Handling
- **Clear Error Messages**: Actionable error descriptions with fix suggestions
- **Problem Identification**: Specific identification of problematic configurations
- **Resolution Guidance**: Step-by-step instructions for fixing issues
- **Prevention Tips**: Guidance to avoid similar issues in the future

## Integration Patterns

### With Bootstrap Module
```yaml
# Bootstrap Configuration
modules:
  mg:
    enabled: true
    environment: "mg"
    scope_id: "/providers/Microsoft.Management/managementGroups/root-mg-id"
    managed_subscriptions:
      - "subscription-1"
      - "subscription-2"
```

### With Network Module
- **Subscription Context**: Provides subscription organization for network deployment
- **Governance Alignment**: Network policies inherit from management group structure
- **Access Control**: Network permissions align with management group hierarchy
- **Compliance Boundaries**: Network isolation follows organizational boundaries

### With Policy Module
- **Policy Scope**: Management groups define policy application boundaries
- **Inheritance Model**: Policies flow down organizational hierarchy
- **Exception Handling**: Selective policy application at appropriate levels
- **Compliance Reporting**: Hierarchical compliance status reporting

## Deployment Considerations

### Prerequisites
- **Service Principal Permissions**: Management Group Contributor role at target scope
- **Subscription Access**: Owner role on managed subscriptions
- **Parent Group Existence**: Root management group must be accessible
- **Configuration Validation**: YAML schema compliance

### Deployment Process
1. **Configuration Validation**: Schema and relationship validation
2. **Dependency Analysis**: Determination of creation order
3. **Level-by-Level Creation**: Systematic hierarchy building
4. **Subscription Assignment**: Attachment of subscriptions to groups
5. **Verification**: Validation of final hierarchy state

### Post-Deployment
- **Hierarchy Verification**: Confirm correct parent-child relationships
- **Subscription Validation**: Verify subscription assignments
- **Permission Testing**: Validate inherited access controls
- **Policy Testing**: Confirm policy inheritance functionality

## Operational Management

### Modification Patterns
```yaml
# Adding New Groups
- id: "new-business-unit"
  display_name: "New Business Unit"
  parent_id: "existing-parent"
  subscriptions: []

# Restructuring Hierarchy
- id: "existing-group"
  display_name: "Updated Display Name"
  parent_id: "new-parent"  # Moving to different parent
  subscriptions: ["updated-subscription-list"]
```

### Change Management
- **Safe Modifications**: Terraform plan shows hierarchy changes
- **Impact Analysis**: Understanding of downstream effects
- **Rollback Capability**: Ability to revert problematic changes
- **Testing Process**: Validation in non-production environments

### Monitoring and Maintenance
- **Hierarchy Drift Detection**: Monitoring for unauthorized changes
- **Subscription Movement Tracking**: Audit trail of subscription changes
- **Policy Compliance Monitoring**: Continuous compliance assessment
- **Access Review Processes**: Regular review of management group permissions

## Best Practices

### Design Principles
- **Stable Foundation**: Design hierarchy to minimize future restructuring
- **Logical Grouping**: Group subscriptions by governance requirements
- **Inheritance Awareness**: Leverage policy and access inheritance effectively
- **Scalability Planning**: Design for organizational growth

### Configuration Management
- **Version Control**: Track all hierarchy changes
- **Environment Separation**: Use different hierarchies for different environments
- **Documentation**: Maintain clear documentation of organizational decisions
- **Validation Testing**: Test changes in non-production environments

### Security Considerations
- **Least Privilege**: Apply minimal required permissions at each level
- **Separation of Duties**: Different teams manage different hierarchy branches
- **Audit Logging**: Comprehensive logging of all changes
- **Access Reviews**: Regular review of management group access

### Operational Excellence
- **Automation**: Minimize manual management group operations
- **Standardization**: Consistent naming and organizational patterns
- **Monitoring**: Proactive monitoring of hierarchy health
- **Training**: Ensure team understanding of management group concepts