terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # rbac_authorization_enabled on azurerm_key_vault first ships in 4.42.
      version = ">= 4.42.0"
    }
  }
}
