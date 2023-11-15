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

variable "storage_account_replication_type" {
  type        = string
  description = "storage account sku (replication type part)"
  validation {
    condition = contains(
      [
        "LRS",
        "ZRS",
        "GRS",
        "RAGRS",
        "GZRS",
        "RAGZRS",
      ],
      var.storage_account_replication_type,
    )
    error_message = "Invalid storage account replication type specified"
  }
}

variable "storage_account_tier" {
  type        = string
  description = "storage account sku (tier part)"
  validation {
    condition = contains(
      [
        "Standard",
        "Premium",
      ],
      var.storage_account_tier,
    )
    error_message = "Invalid storage account tier specified"
  }
}

variable "storage_account_kind" {
  type        = string
  description = "storage account kind"
  validation {
    condition = contains(
      [
        "BlobStorage",
        "BlockBlobStorage",
        "FileStorage",
        "Storage",
        "StorageV2",
      ],
      var.storage_account_kind,
    )
    error_message = "Invalid storage account kind specified"
  }
}

variable "storage_account_public_access_enabled" {
  type        = bool
  description = "Whether public access is enabled for the storage account?"
}

resource "azurerm_resource_group" "test" {
  name     = "${var.prefix}-resoruce-group"
  location = "westeurope"
}

resource "azapi_resource" "storage_account" {
  parent_id = azurerm_resource_group.test.id
  type      = "Microsoft.Storage/storageAccounts@2023-01-01"
  name      = "${var.prefix}testsa20231115"
  location  = azurerm_resource_group.test.location
  body = jsonencode({
    kind = var.storage_account_kind
    properties = {
      accessTier                   = "Hot"
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
      name = "${var.storage_account_tier}_${var.storage_account_replication_type}"
    }
  })
  response_export_values = ["*"]
}

resource "azapi_resource" "storage_container" {
  parent_id = "${azapi_resource.storage_account.id}/blobServices/default"
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
  type                   = "Microsoft.Storage/storageAccounts@2023-01-01"
  resource_id            = azapi_resource.storage_account.id
  action                 = "listKeys"
  response_export_values = ["*"]
}

data "azurerm_storage_account_sas" "test" {
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${azapi_resource.storage_account.name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys.output).keys[0].value};EndpointSuffix=core.windows.net"
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
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${azapi_resource.storage_account.name};AccountKey=${jsondecode(data.azapi_resource_action.list_keys.output).keys[0].value};EndpointSuffix=core.windows.net"
  container_name    = azapi_resource.storage_container.name
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
  provisioner "local-exec" {
    command = "curl -X PUT --data-raw \"<StorageServiceProperties><StaticWebsite><Enabled>true</Enabled><IndexDocument>index.html</IndexDocument></StaticWebsite></StorageServiceProperties>\" \"${jsondecode(azapi_resource.storage_account.output).properties.primaryEndpoints.blob}${data.azurerm_storage_account_sas.test.sas}&restype=service&comp=properties\""
  }

  provisioner "local-exec" {
    command = "curl -X PUT -T index.html -H 'x-ms-blob-type: BlockBlob' -H 'x-ms-blob-content-type: text/html' '${jsondecode(azapi_resource.storage_account.output).properties.primaryEndpoints.blob}${azapi_resource.storage_container.name}/index.html${data.azurerm_storage_account_blob_container_sas.test.sas}'"
  }
}

# output "upload_url" {
#   value     = "${jsondecode(azapi_resource.storage_account.output).properties.primaryEndpoints.blob}${azapi_resource.storage_container.name}${data.azurerm_storage_account_blob_container_sas.test.sas}"
#   sensitive = true
# }

# output "service_sas" {
#   value     = "${jsondecode(azapi_resource.storage_account.output).properties.primaryEndpoints.blob}${data.azurerm_storage_account_sas.test.sas}"
#   sensitive = true
# }
