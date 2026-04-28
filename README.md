# Overview

# Redpanda Azure BYOVNet Terraform Module

This Terraform module provisions the necessary Azure infrastructure for a Redpanda BYOVNet cluster. It configures managed
identities, role assignments, network security groups, VNet components, and storage resources required for deploying
Redpanda in a customer's Azure environment.

## Module Overview

This module deploys several core components:

1. **Resource Groups**: Creates resource groups for organizing Redpanda resources (main, storage, network, and IAM)
2. **Managed Identities**: Creates user-assigned managed identities for various Redpanda components (agent, cert-manager, external-dns, cluster, AKS, console, kafka-connect, redpanda-connect, etc.)
3. **Network Infrastructure**: Provisions VNet, private subnets, egress subnets, and network security groups
4. **Storage Resources**: Creates Azure Storage Accounts and containers for management and tiered storage
5. **Key Vaults**: Creates Azure Key Vaults for secure secrets management
6. **Role Assignments**: Configures custom role definitions and assigns appropriate permissions to managed identities

## Guidance

1. The module can create a new VNet or use an existing one by providing `vnet_name`.
2. Private and egress subnets are configured with appropriate service endpoints for Azure Storage, Key Vault, and Azure Active Directory.
3. The tags specified in `tags` are applied to all resources for consistent resource management.
4. Multiple subnets are created to support AKS node pools for different Redpanda components (system, agent, cluster nodes, connect).
5. Storage accounts use Zone-Redundant Storage (ZRS) for high availability and have hierarchical namespace enabled.

## Examples

### Basic Usage where module will create the VNet

```terraform
module "redpanda_byovnet" {
  source = "redpanda-data/redpanda-byovnet/azure"

  region = "eastus"

  resource_name_prefix       = "prod-rp-"
  resource_group_name_prefix = "prod-"

  azure_tenant_id       = "your-tenant-id"
  azure_subscription_id = "your-subscription-id"

  create_resource_groups = true

  vnet_addresses = ["10.0.0.0/20"]

  private_subnets = {
    "system-pod" : {
      "cidr" : "10.0.1.0/24",
      "name" : "snet-system-pods"
    },
    "system-vnet" : {
      "cidr" : "10.0.2.0/24",
      "name" : "snet-system-vnet"
    },
    "agent-private" : {
      "cidr" : "10.0.3.0/24",
      "name" : "snet-agent-private"
    },
    "rp-0-pods" : {
      "cidr" : "10.0.4.0/24",
      "name" : "snet-rp-0-pods"
    },
    "rp-0-vnet" : {
      "cidr" : "10.0.5.0/24",
      "name" : "snet-rp-0-vnet"
    }
  }

  egress_subnets = {
    "agent-public" : {
      "cidr" : "10.0.0.0/24",
      "name" : "snet-agent-public"
    }
  }

  tags = {
    "Environment" = "production"
    "Project"     = "redpanda"
    "Terraform"   = "true"
  }
}
```

### Using Existing VNet

```terraform
module "redpanda_byovnet" {
  source = "redpanda-data/redpanda-byovnet/azure"

  region = "eastus"

  resource_name_prefix       = "dev-rp-"
  resource_group_name_prefix = "dev-"

  azure_tenant_id       = "your-tenant-id"
  azure_subscription_id = "your-subscription-id"

  vnet_name              = "existing-vnet-name"
  create_resource_groups = false

  redpanda_resource_group_name = "existing-redpanda-rg"
  redpanda_storage_resource_group_name = "existing-storage-rg"
  redpanda_network_resource_group_name = "existing-network-rg"
  redpanda_iam_resource_group_name = "existing-iam-rg"

  tags = {
    "Environment" = "development"
    "Project"     = "redpanda"
    "Terraform"   = "true"
  }
}
```

### With Custom Storage and Key Vault Names

```terraform
module "redpanda_byovnet" {
  source = "redpanda-data/redpanda-byovnet/azure"

  region = "westus2"

  resource_name_prefix       = "staging-rp-"
  resource_group_name_prefix = "staging-"

  azure_tenant_id       = "your-tenant-id"
  azure_subscription_id = "your-subscription-id"

  create_resource_groups = true

  redpanda_management_storage_account_name   = "mgmtstorage"
  redpanda_management_storage_container_name = "mgmtcontainer"
  redpanda_tiered_storage_account_name       = "tieredstorage"
  redpanda_tiered_storage_container_name     = "tieredcontainer"

  redpanda_management_key_vault_name = "rp-mgmt-vault"
  redpanda_console_key_vault_name    = "rp-console-vault"

  tags = {
    "Environment" = "staging"
    "Project"     = "redpanda"
    "Terraform"   = "true"
  }
}
```

## Grant Your User Storage Access

The management storage account has shared access keys disabled and requires Azure AD authentication. The identity running `rpk apply` must have the **Storage Blob Data Contributor** role on the management storage account.

This can be codified in Terraform by setting `grant_caller_management_storage_access = true` in your `byovnet.auto.tfvars.json`:

```json
"grant_caller_management_storage_access": true
```

This grants the identity running `rpk apply` the role automatically. Alternatively, you can assign the role manually:

```shell
ACCOUNT=$(terraform output -raw management_bucket_storage_account_name)
RESOURCE_GROUP=$(terraform output -raw redpanda_resource_group_name)
SCOPE=$(az storage account show --name "$ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Storage Blob Data Contributor" \
  --scope "$SCOPE"
```

> Note: Azure RBAC propagation can take a few minutes. If you see a 403 error immediately after, wait briefly and retry.
