terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

variable "prefix" {
  type        = string
  description = "Resource name prefix"
}

variable "storage_account_name" {
  type        = string
  description = "The name of the storage account to check"
}

data "azurerm_resource_group" "test" {
  name = "${var.prefix}-resoruce-group"
}

data "azapi_resource" "storage_account" {
  parent_id              = data.azurerm_resource_group.test.id
  type                   = "Microsoft.Storage/storageAccounts@2023-01-01"
  name                   = var.storage_account_name
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

data "azurerm_storage_account_blob_container_sas" "blob" {
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${data.azapi_resource.storage_account.name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys.output).keys[0].value};EndpointSuffix=core.windows.net"
  container_name    = data.azapi_resource.storage_container.name
  https_only        = true

  start  = "2023-11-14"
  expiry = "2025-11-14"

  permissions {
    create = false
    read   = true
    add    = false
    write  = false
    delete = false
    list   = false
  }

  content_type = "text/html"
}

data "azurerm_storage_account_blob_container_sas" "prop" {
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${data.azapi_resource.storage_account.name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys.output).keys[0].value};EndpointSuffix=core.windows.net"
  container_name    = data.azapi_resource.storage_container.name
  https_only        = true

  start  = "2023-11-14"
  expiry = "2025-11-14"

  permissions {
    create = false
    read   = true
    add    = false
    write  = false
    delete = false
    list   = true
  }

  content_type = "application/xml"
}

locals {
  blob_endpoint = jsondecode(data.azapi_resource.storage_account.output).properties.primaryEndpoints.blob
  web_endpoint  = jsondecode(data.azapi_resource.storage_account.output).properties.primaryEndpoints.web
}

check "blob_service_property" {
  data "http" "svc" {
    url = "${local.blob_endpoint}${data.azurerm_storage_account_sas.test.sas}&restype=service&comp=properties"
  }

  assert {
    condition     = data.http.svc.status_code == 200
    error_message = "${var.storage_account_name}: failed to get the blob service properties (status_code=${data.http.svc.status_code})"
  }

  assert {
    condition     = strcontains(data.http.svc.response_body, "<StaticWebsite><Enabled>true")
    error_message = "${var.storage_account_name}: web not enabled (${regex("<StaticWebsite>.*</StaticWebsite>", data.http.svc.response_body)})"
  }
}

check "container_property" {
  data "http" "container" {
    url = "${local.blob_endpoint}${data.azapi_resource.storage_container.name}${data.azurerm_storage_account_blob_container_sas.prop.sas}&restype=container&comp=list"
  }

  assert {
    condition     = data.http.container.status_code == 200
    error_message = "${var.storage_account_name}: failed to access the container properties (status_code=${data.http.container.status_code})"
  }
}

check "container_blob" {
  data "http" "blob" {
    url = "${local.blob_endpoint}${data.azapi_resource.storage_container.name}/index.html${data.azurerm_storage_account_blob_container_sas.blob.sas}"
  }

  assert {
    condition     = data.http.blob.status_code == 200
    error_message = "${var.storage_account_name}: failed to access the container blob (status_code=${data.http.blob.status_code})"
  }
}

check "access_web_page" {
  data "http" "web" {
    url = local.web_endpoint
  }

  assert {
    condition     = data.http.web.status_code == 200
    error_message = "${var.storage_account_name}: failed to access the web page (status_code=${data.http.web.status_code})"
  }
}
