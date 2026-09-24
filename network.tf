locals {
  vnet      = data.azurerm_virtual_network.redpanda
  vnet_name = local.vnet.name
}

resource "azurerm_virtual_network" "redpanda" {
  count               = var.vnet_name == "" ? 1 : 0
  name                = "${var.resource_name_prefix}rp-vnet"
  location            = var.region
  resource_group_name = local.redpanda_network_resource_group_name
  address_space       = var.vnet_addresses

  tags = var.tags

  depends_on = [azurerm_resource_group.all]
}

data "azurerm_virtual_network" "redpanda" {
  name                = var.vnet_name == "" ? azurerm_virtual_network.redpanda[0].name : var.vnet_name
  resource_group_name = local.redpanda_network_resource_group_name
}

# The Redpanda BYOC agent reads a subnet's range only from the singular
# addressPrefix (GetVNet in cloudv2 pkg/azuresdk/client) and reports a subnet
# without it as missing, which fails cluster creation. azurerm 5 sends only
# addressPrefixes, on create and on every update, and Azure keeps a subnet in
# the plural form once it has been written that way. So the subnets are
# created and managed through azapi with the singular form.
locals {
  subnet_service_endpoints = [
    # Use Azure's internal network to reach out to the following Azure services
    { service = "Microsoft.Storage.Global" },
    { service = "Microsoft.AzureActiveDirectory" },
    { service = "Microsoft.KeyVault" },
  ]

  # AKS delegates the subnets it uses after create. ignore_body_changes only
  # substitutes live values for keys present in body, so body carries an
  # empty delegations list for an update to fill with the live one.
  subnet_ignore_body_changes = ["properties.delegations"]
}

resource "azapi_resource" "private_subnet" {
  for_each = var.private_subnets

  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "${var.resource_name_prefix}${each.value.name}"
  parent_id = local.vnet.id
  body = {
    properties = {
      addressPrefix                  = each.value.cidr
      privateEndpointNetworkPolicies = "Enabled"
      serviceEndpoints               = local.subnet_service_endpoints
      delegations                    = []
      # Set here rather than through azurerm_subnet_nat_gateway_association:
      # an azapi update omits whatever body leaves out, which would detach
      # the gateway.
      natGateway = var.create_nat ? { id = azurerm_nat_gateway.redpanda[0].id } : null
    }
  }
  ignore_body_changes = local.subnet_ignore_body_changes
  # Azure keeps the endpoint order a subnet was created with, and v1 created
  # them in azurerm 4's hash order; match by service, not by position.
  list_unique_id_property = { "properties.serviceEndpoints" = "service" }

  # Subnet writes on one VNet conflict with AnotherOperationInProgress.
  locks = [local.vnet.id]
  retry = { error_message_regex = ["AnotherOperationInProgress"] }
}

resource "azapi_resource" "public_subnet" {
  for_each = var.egress_subnets

  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "${var.resource_name_prefix}${each.value.name}"
  parent_id = local.vnet.id
  body = {
    properties = {
      addressPrefix                  = each.value.cidr
      privateEndpointNetworkPolicies = "Enabled"
      serviceEndpoints               = local.subnet_service_endpoints
      delegations                    = []
    }
  }
  ignore_body_changes = local.subnet_ignore_body_changes
  # Azure keeps the endpoint order a subnet was created with, and v1 created
  # them in azurerm 4's hash order; match by service, not by position.
  list_unique_id_property = { "properties.serviceEndpoints" = "service" }

  locks = [local.vnet.id]
  retry = { error_message_regex = ["AnotherOperationInProgress"] }
}

# v1.x managed these subnets as azurerm_subnet; adopt them in place.
moved {
  from = azurerm_subnet.private
  to   = azapi_resource.private_subnet
}

moved {
  from = azurerm_subnet.public
  to   = azapi_resource.public_subnet
}

# The NAT gateway is now part of each private subnet's body. Destroying the
# v1 association would detach it, so drop it from state instead.
removed {
  from = azurerm_subnet_nat_gateway_association.redpanda

  lifecycle {
    destroy = false
  }
}
