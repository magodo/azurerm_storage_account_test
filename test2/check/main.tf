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

data "azurerm_resource_group" "test" {
  name = "${var.prefix}-resoruce-group"
}

data "azapi_resource" "storage_account" {
  parent_id              = data.azurerm_resource_group.test.id
  type                   = "Microsoft.Storage/storageAccounts@2023-01-01"
  name                   = "${var.prefix}testsa20231115"
  response_export_values = ["*"]
}

data "azapi_resource" "storage_container" {
  parent_id              = "${data.azapi_resource.storage_account.id}/blobServices/default"
  type                   = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  name                   = "$web"
  response_export_values = ["*"]
}

data "azapi_resource_action" "list_keys" {
  type                   = "Microsoft.Storage/storageAccounts@2023-01-01"
  resource_id            = data.azapi_resource.storage_account.id
  action                 = "listKeys"
  response_export_values = ["*"]
}

data "azurerm_storage_account_sas" "test" {
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${data.azapi_resource.storage_account.name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys.output).keys[0].value};EndpointSuffix=core.windows.net"
  https_only        = true
  signed_version    = "2022-11-02"

  resource_types {
    service   = true
    container = false
    object    = false
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = "2023-11-14"
  expiry = "2025-11-14"

  permissions {
    read    = true
    write   = true
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

check "blob_service_property" {
  data "http" "svc" {
    url = "${local.blob_endpoint}${data.azurerm_storage_account_sas.test.sas}&restype=service&comp=properties"
  }

  assert {
    condition     = data.http.svc.status_code == 200
    error_message = "failed to get the blob service properties (status_code=${data.http.svc.status_code})"
  }

  assert {
    condition     = strcontains(data.http.svc.response_body, "<StaticWebsite><Enabled>true")
    error_message = "web not enabled (${regex("<StaticWebsite>.*</StaticWebsite>", data.http.svc.response_body)})"
  }
}

check "access_web_page" {
  data "http" "web" {
    url = local.web_endpoint
  }

  assert {
    condition     = data.http.web.status_code == 200
    error_message = "failed to access the web page (status_code=${data.http.web.status_code})"
  }
}


locals {
  blob_endpoint = jsondecode(data.azapi_resource.storage_account.output).properties.primaryEndpoints.blob
  web_endpoint  = jsondecode(data.azapi_resource.storage_account.output).properties.primaryEndpoints.web
}
