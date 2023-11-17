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

# variable "storage_account_replication_type" {
#   type        = string
#   description = "storage account sku (replication type part)"
#   validation {
#     condition = contains(
#       [
#         "LRS",
#         "ZRS",
#         "GRS",
#         "RAGRS",
#         "GZRS",
#         "RAGZRS",
#       ],
#       var.storage_account_replication_type,
#     )
#     error_message = "Invalid storage account replication type specified"
#   }
# }

# variable "storage_account_tier" {
#   type        = string
#   description = "storage account sku (tier part)"
#   validation {
#     condition = contains(
#       [
#         "Standard",
#         "Premium",
#       ],
#       var.storage_account_tier,
#     )
#     error_message = "Invalid storage account tier specified"
#   }
# }

# variable "storage_account_kind" {
#   type        = string
#   description = "storage account kind"
#   validation {
#     condition = contains(
#       [
#         "BlobStorage",
#         "BlockBlobStorage",
#         "FileStorage",
#         "Storage",
#         "StorageV2",
#       ],
#       var.storage_account_kind,
#     )
#     error_message = "Invalid storage account kind specified"
#   }
# }

variable "storage_account_public_access_enabled" {
  type        = bool
  description = "Whether public access is enabled for the storage account?"
}

locals {
  sa_list = { for t in setproduct(
    ["BlockBlobStorage", "StorageV2"],
    # From https://learn.microsoft.com/en-us/rest/api/storagerp/storage-accounts/create?view=rest-storagerp-2023-01-01&tabs=HTTP#skuname
    [
      "Premium_LRS",
      "Premium_ZRS",
      "Standard_GRS",
      "Standard_GZRS",
      "Standard_LRS",
      "Standard_RAGRS",
      "Standard_RAGZRS",
      "Standard_ZRS",
    ],
    # key is in the form of: <prefix><kind len=1><sku (underscore removed)>
    ) : lower("${var.prefix}${substr(t[0], 0, 1)}${replace(t[1], "_", "")}") => {
    kind = t[0]
    sku  = t[1]
    } if alltrue(
    [
      # From: https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts
      # > ZRS, GZRS, and RA-GZRS are available only for standard general-purpose v2, premium block blobs, premium file shares, and premium page blobs accounts in certain regions
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_ZRS"),
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_GZRS"),
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_RAGRS"),
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_GRS"),
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_RAGZRS"),

      # Not sure why the below also failed, but is not documented:
      # Error: Values for request parameters are invalid: kind, sku. For more information, see - https://aka.ms/storageaccounttypes
      !(t[0] == "BlockBlobStorage" && t[1] == "Standard_LRS"),

      # Storage account can be created, while failed to create the container ($web)
      # Error: Server encountered an internal error. Please try again after some time.
      !(t[0] == "StorageV2" && t[1] == "Premium_ZRS"),

      # Storage account and container can be created, while failed to setup the web
      # Error of enabling web: 
      # b'\xef\xbb\xbf<?xml version="1.0" encoding="utf-8"?>\n<Error><Code>InvalidXmlDocument</Code><Message>XML specified is not syntactically valid.</Message><Reason>StaticWebsite element is allowed only for Blob service with REST versions starting from 2018-03-28.</Reason></Error>'
      # Error of upload the blob:
      # b'\xef\xbb\xbf<?xml version="1.0" encoding="utf-8"?>\n<Error><Code>BlobTypeNotSupported</Code><Message>Block blobs are not supported.</Message></Error>'
      !(t[0] == "StorageV2" && t[1] == "Premium_LRS"),
    ]
    )
  }
}

resource "azurerm_resource_group" "test" {
  name     = "${var.prefix}-resoruce-group"
  location = "westeurope"
}

resource "azapi_resource" "storage_account" {
  for_each  = local.sa_list
  parent_id = azurerm_resource_group.test.id
  type      = "Microsoft.Storage/storageAccounts@2023-01-01"
  name      = each.key
  location  = azurerm_resource_group.test.location
  body = jsonencode({
    kind = each.value.kind
    properties = {
      allowBlobPublicAccess        = false
      allowCrossTenantReplication  = false
      allowSharedKeyAccess         = true
      defaultToOAuthAuthentication = false
      dnsEndpointType              = "Standard"
      encryption = {
        keySource                       = "Microsoft.Storage"
        requireInfrastructureEncryption = false
        services = {
          blob = {
            enabled = true
            keyType = "Account"
          }
          file = {
            enabled = true
            keyType = "Account"
          }
        }
      }
      minimumTlsVersion = "TLS1_2"
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = "Allow"
        ipRules             = []
        resourceAccessRules = []
        virtualNetworkRules = []
      }
      publicNetworkAccess      = var.storage_account_public_access_enabled ? "Enabled" : "Disabled"
      supportsHttpsTrafficOnly = true
    }
    sku = {
      name = each.value.sku
    }
  })
  response_export_values = ["*"]
}

resource "azapi_resource" "storage_container" {
  for_each  = local.sa_list
  parent_id = "${azapi_resource.storage_account[each.key].id}/blobServices/default"
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  name      = "$web"
  body = jsonencode({
    properties = {
      defaultEncryptionScope      = "$account-encryption-key"
      denyEncryptionScopeOverride = false
      publicAccess                = "None"
    }
  })
}

data "azapi_resource_action" "list_keys" {
  for_each               = local.sa_list
  type                   = "Microsoft.Storage/storageAccounts@2023-01-01"
  resource_id            = azapi_resource.storage_account[each.key].id
  action                 = "listKeys"
  response_export_values = ["*"]
}

data "azurerm_storage_account_sas" "test" {
  for_each          = local.sa_list
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${azapi_resource.storage_account[each.key].name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys[each.key].output).keys[0].value};EndpointSuffix=core.windows.net"
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


data "azurerm_storage_account_blob_container_sas" "test" {
  for_each          = local.sa_list
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${azapi_resource.storage_account[each.key].name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys[each.key].output).keys[0].value};EndpointSuffix=core.windows.net"
  container_name    = azapi_resource.storage_container[each.key].name
  https_only        = true

  start  = "2023-11-14"
  expiry = "2025-11-14"

  permissions {
    create = true
    read   = false
    add    = false
    write  = false
    delete = false
    list   = false
  }

  content_type = "text/html"
}

// This null resource enables the static web site and upload the index.html, via data plane APIs
resource "null_resource" "setup_storage_account_static_web" {
  for_each = local.sa_list
  provisioner "local-exec" {
    command = "curl -X PUT --data-raw \"<StorageServiceProperties><StaticWebsite><Enabled>true</Enabled><IndexDocument>index.html</IndexDocument></StaticWebsite></StorageServiceProperties>\" \"${jsondecode(azapi_resource.storage_account[each.key].output).properties.primaryEndpoints.blob}${data.azurerm_storage_account_sas.test[each.key].sas}&restype=service&comp=properties\""
  }

  provisioner "local-exec" {
    command = "curl -X PUT -T index.html -H 'x-ms-blob-type: BlockBlob' -H 'x-ms-blob-content-type: text/html' '${jsondecode(azapi_resource.storage_account[each.key].output).properties.primaryEndpoints.blob}${azapi_resource.storage_container[each.key].name}/index.html${data.azurerm_storage_account_blob_container_sas.test[each.key].sas}'"
  }
}

output "sa_list" {
  value = keys(local.sa_list)
}

output "prefix" {
  value = var.prefix
}
