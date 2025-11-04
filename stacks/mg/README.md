# Management Groups Module (Azure Landing Zones)

This Terraform module creates and manages an **Azure Management Group (MG) hierarchy** and **subscription attachments** from a single YAML file. It’s designed to be **flat, composable, and predictable**, so it can be used independently from networking (hub/spoke) or other landing-zone components.

## Repo Layout

```
landing-zones/
├── modules/
│   └── mg/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── stacks/
│   └── mg/
│       ├── main.tf
│       └── versions.tf
├── configs/
│   ├── mg.yaml               # example config
├── .gitignore
└── README.md
```

---

## YAML Schema (v1)

```yaml
schema_version: 1

management_groups:
  - id: <string>                 # unique in file; becomes the MG name
    display_name: <string>
    parent_id: root | <mg-id>    # 'root' or another mg id defined in this file
    subscriptions:               # optional; list of subscription GUIDs
      - "00000000-0000-0000-0000-000000000000"
```

---

## How It Works

### Input normalization
- `mg_input`: list of MG objects (or `[]`).
- `sub_input`: flattened list of `{ subscription_id, target_mg_id }` created from nested `subscriptions`. Subscription IDs are normalized with `trimspace(lower(...))`.
- `mg_map`: `id -> mg` for quick lookups.

### Depth bucketing (graph layering)
- `level0`: MGs whose `parent_id == "root"`.
- `level1`: MGs whose parent is in `level0`.
- …
- `level6`: MGs whose parent is in `level5`.

Each level maps to one `azurerm_management_group` resource block (`mg_l0` … `mg_l6`) with `for_each`. Children link to parents in the **previous level**, yielding a stable, acyclic graph. Max supported depth is **6 below root** (root + L0..L6).

### Guards (fail fast)
Preconditions that stop bad plans early with friendly messages:
- **Duplicate MG ids** (must be unique).
- **Missing parent** (child points to non-existent MG in this file).
- **Subscription GUID format** (basic regex).
- **Same subscription under multiple MGs** (subscription can attach to only one MG).
- **Depth > 6** (lists the “too-deep” MG ids).

### Unified view for wiring & outputs
- `mg_all`: post-plan canonical map of MG id → `{ arm_id, display_name, parent_id }`, composed from all level resources.
- `subs_by_mg`: MG id → list of subscription GUIDs, filtered against `mg_all` so reparent/delete changes don’t cause invalid indexes during the same plan.

### Outputs
- **`mg_ids`**: `map(string => string)` — MG id → ARM resource id  
- **`tree`**: `list(object)` — per-MG `id`, `display_name`, `parent_id`, and `subscriptions`

---

## Permissions & Auth

The identity running Terraform must be able to **read tenant info** and **manage management groups and subscription associations**:

- Typically: **Tenant Root Group Contributor** or **Management Group Contributor** at the appropriate scope.
- To move subscriptions: **Owner/Contributor** on the subscription **and** write on the target MG scope.

The module uses `data "azurerm_client_config" "current"` to read the active tenant/account.

**Authenticate to Azure (CLI):**
```bash
az login
# Optional: ensure correct tenant
az account tenant set --tenant <TENANT_ID>
```

---

## Quick Start

```bash
# 1) Prepare
cd stacks/mg
az login

# 2) Initialize Terraform
terraform init

# 3) Review changes
terraform plan

# 4) Apply
terraform apply

# 5) Outputs
terraform output mg_ids
terraform output -json tree | jq .
```
