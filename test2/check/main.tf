terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

provider "azapi" {
  skip_provider_registration = false
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "prefix" {
  type        = string
  description = "Resource name prefix"
}

variable "sa_list" {
  type        = set(any)
  description = "The list of storage account names to check"
}

module "check" {
  for_each             = var.sa_list
  source               = "./check_module"
  prefix               = var.prefix
  storage_account_name = each.value
}
