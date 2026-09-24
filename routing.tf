locals {
  create_nat = var.create_nat ? 1 : 0
  // zone ids used for resources bound to the NAT gateways
  natg_zone_ids = [
    for m in data.azurerm_location.redpanda.zone_mappings :
    m.logical_zone if m.physical_zone == try(var.zones[0], "")
  ]
  natg_zone_error = (
    length(data.azurerm_location.redpanda.zone_mappings) == 0
    ? "region ${var.region} reports no availability zones, so create_nat = true cannot work there."
    : "zones[0] must be a physical availability zone of region ${var.region}, such as ${var.region}-az1; got zones = ${jsonencode(var.zones)}."
  )
}

resource "azurerm_nat_gateway" "redpanda" {
  count                   = local.create_nat
  name                    = "${var.resource_name_prefix}ngw-${var.region}"
  location                = var.region
  resource_group_name     = local.redpanda_network_resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = [element(local.natg_zone_ids, 0)]

  tags = var.tags

  depends_on = [azurerm_resource_group.all]

  lifecycle {
    precondition {
      condition     = length(local.natg_zone_ids) > 0
      error_message = local.natg_zone_error
    }
  }
}

resource "azurerm_public_ip_prefix" "redpanda" {
  count               = local.create_nat
  name                = "${var.resource_name_prefix}ippre-${var.region}"
  location            = var.region
  resource_group_name = local.redpanda_network_resource_group_name
  prefix_length       = 31 # 2 IPs should offer more than enough source ports: 128k
  zones               = [element(local.natg_zone_ids, 0)]
  sku                 = "Standard"

  tags = var.tags

  depends_on = [azurerm_resource_group.all]

  lifecycle {
    precondition {
      condition     = length(local.natg_zone_ids) > 0
      error_message = local.natg_zone_error
    }
  }
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "redpanda" {
  count               = local.create_nat
  nat_gateway_id      = azurerm_nat_gateway.redpanda[0].id
  public_ip_prefix_id = azurerm_public_ip_prefix.redpanda[0].id
}
