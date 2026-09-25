###########################################################################
# General vars
###########################################################################
variable "region" {
  type        = string
  default     = "eastus"
  description = <<-HELP
    The region where the resources live.
  HELP
}

variable "zones" {
  type        = list(string)
  default     = ["eastus-az2"]
  description = <<-HELP
    Physical availability zone IDs in var.region. Ex: eastus-az1, eastus-az3, eastus-az2
    The NAT gateway is placed in the first one. The default only fits
    region = "eastus"; set both together.
  HELP
}

variable "tags" {
  type        = map(string)
  description = <<-HELP
    Tags to use when labeling resources. These will be set inside the provider block
    as default tags.
  HELP
}

variable "resource_name_prefix" {
  type        = string
  default     = "pz-"
  description = <<-HELP
    The prefix added to the name of non resource group resource.
  HELP
}

variable "resource_group_name_prefix" {
  type        = string
  default     = ""
  description = <<-HELP
    The prefix added to the name of resource group.
  HELP
}
