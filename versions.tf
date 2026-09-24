terraform {
  # moved blocks across resource types (azurerm_subnet to azapi_resource)
  # need 1.8.
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.0 requires rbac_authorization_enabled on azurerm_key_vault; 5.5 adds
      # public_network_access on azurerm_storage_account.
      version = ">= 5.5.0, < 6.0.0"
    }
    azapi = {
      source = "Azure/azapi"
      # 2.12 brings back ignore_body_changes on azapi_resource and fixes moves
      # from azurerm resources.
      version = ">= 2.12.0, < 3.0.0"
    }
  }
}
