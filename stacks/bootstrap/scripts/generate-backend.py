#!/usr/bin/env python3
import yaml
import sys
import os

# Read bootstrap.yaml
config_file = "../../configs/bootstrap.yaml"
backend_file = "backend.hcl"

try:
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    
    tfstate = config['tfstate']
    
    # Generate backend.hcl
    backend_content = f'''resource_group_name  = "{tfstate['resource_group']}"
storage_account_name = "{tfstate['storage_account']}"
container_name       = "{tfstate['container']}"
key                  = "bootstrap.tfstate"
subscription_id      = "{tfstate['subscription_id']}"
use_azuread_auth     = true'''
    
    with open(backend_file, 'w') as f:
        f.write(backend_content)
    
    print(f" Generated {backend_file} from {config_file}")
    print("Contents:")
    print(backend_content)
    
except Exception as e:
    print(f" Error: {e}", file=sys.stderr)
    sys.exit(1)