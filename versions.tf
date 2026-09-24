terraform {
  # Preconditions in routing.tf need 1.2.
  required_version = ">= 1.2"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.0 requires rbac_authorization_enabled on azurerm_key_vault and
      # replaced the azurerm_subnet service_endpoints list with the
      # service_endpoint block. Neither form works on both majors.
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}
