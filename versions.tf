terraform {
  # Preconditions in routing.tf need 1.2.
  required_version = ">= 1.2"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.42 adds rbac_authorization_enabled on azurerm_key_vault. 5.0 drops
      # service_endpoints from azurerm_subnet, which network.tf sets.
      version = ">= 4.42.0, < 5.0.0"
    }
  }
}
