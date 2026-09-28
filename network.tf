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
#
# Each subnet is two resources. azapi_resource creates it and never writes it
# again: its update PUTs only body, which would clear what others attach
# after create (AKS delegations, and a caller's route table, NSG, or, with
# create_nat = false, NAT gateway). azapi_update_resource applies the fields
# this module owns by reading the live subnet and merging them in, so those
# attachments survive.
locals {
  subnet_service_endpoints = [
    # Use Azure's internal network to reach out to the following Azure services
    { service = "Microsoft.Storage.Global" },
    { service = "Microsoft.AzureActiveDirectory" },
    { service = "Microsoft.KeyVault" },
  ]

  # Empty unless the module owns the NAT gateway, so a caller's gateway is
  # left as it is.
  subnet_nat_gateway = { for id in azurerm_nat_gateway.redpanda[*].id : "natGateway" => { id = id } }
}

resource "azapi_resource" "private_subnet" {
  for_each = var.private_subnets

  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "${var.resource_name_prefix}${each.value.name}"
  parent_id = local.vnet.id
  body = {
    properties = merge({
      addressPrefix                  = each.value.cidr
      privateEndpointNetworkPolicies = "Enabled"
      serviceEndpoints               = local.subnet_service_endpoints
    }, local.subnet_nat_gateway)
  }

  # Subnet writes on one VNet conflict with AnotherOperationInProgress.
  locks = [local.vnet.id]
  retry = { error_message_regex = ["AnotherOperationInProgress"] }

  lifecycle {
    # locks applies on create. A locks change would otherwise PUT the
    # subnet, which subnets adopted from v1 (no locks in state) hit. retry
    # stays managed: azapi applies it without a request, and delete reads
    # it from state, so adopted subnets need it to retry conflicting deletes.
    ignore_changes = [body, locks]
  }
}

resource "azapi_update_resource" "private_subnet" {
  for_each = azapi_resource.private_subnet

  type        = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id = each.value.id
  body = {
    properties = merge({
      addressPrefix                  = var.private_subnets[each.key].cidr
      privateEndpointNetworkPolicies = "Enabled"
      serviceEndpoints               = local.subnet_service_endpoints
    }, local.subnet_nat_gateway)
  }
  # Azure keeps the endpoint order a subnet was created with, and v1 created
  # them in azurerm 4's hash order; match by service, not by position.
  list_unique_id_property = { "properties.serviceEndpoints" = "service" }

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
    }
  }

  locks = [local.vnet.id]
  retry = { error_message_regex = ["AnotherOperationInProgress"] }

  lifecycle {
    # locks applies on create. A locks change would otherwise PUT the
    # subnet, which subnets adopted from v1 (no locks in state) hit. retry
    # stays managed: azapi applies it without a request, and delete reads
    # it from state, so adopted subnets need it to retry conflicting deletes.
    ignore_changes = [body, locks]
  }
}

resource "azapi_update_resource" "public_subnet" {
  for_each = azapi_resource.public_subnet

  type        = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id = each.value.id
  body = {
    properties = {
      addressPrefix                  = var.egress_subnets[each.key].cidr
      privateEndpointNetworkPolicies = "Enabled"
      serviceEndpoints               = local.subnet_service_endpoints
    }
  }
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

# The module's NAT gateway is now set through the subnets themselves.
# Destroying the v1 association would detach it, so drop it from state
# instead.
removed {
  from = azurerm_subnet_nat_gateway_association.redpanda

  lifecycle {
    destroy = false
  }
}
