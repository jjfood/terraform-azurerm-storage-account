provider "azurerm" {
  storage_use_azuread = true
}

resource "random_string" "random" {
  length  = 24
  special = false
  upper   = false
}

resource "azurecaf_name" "rg" {
  name          = "${var.name}-state"
  resource_type = "azurerm_resource_group"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurerm_resource_group" "state" {
  name     = azurecaf_name.rg.result
  location = var.location
  tags     = var.tags
}

resource "azurecaf_name" "storage" {
  name          = "${var.name}state"
  resource_type = "azurerm_storage_account"
  suffixes      = [lower(var.environment)]
  random_length = 4
}

resource "azurerm_storage_account" "sa" {
  name                     = azurecaf_name.storage.result
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_kind             = var.account_kind
  account_tier             = local.account_tier
  account_replication_type = var.replication_type
  access_tier              = var.access_tier
  tags                     = var.tags

  is_hns_enabled                    = var.enable_hns
  sftp_enabled                      = var.enable_sftp
  large_file_share_enabled          = var.enable_large_file_share
  allow_nested_items_to_be_public   = var.allow_nested_items_to_be_public
  enable_https_traffic_only         = var.enable_https_traffic_only
  min_tls_version                   = var.min_tls_version
  nfsv3_enabled                     = var.nfsv3_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled
  public_network_access_enabled     = var.private_endpoint_subnet_id == null ? true : false

  identity {
    type = "SystemAssigned"
  }

  dynamic "blob_properties" {
    for_each = ((var.account_kind == "BlockBlobStorage" || var.account_kind == "StorageV2") ? [1] : [])
    content {
      versioning_enabled = var.blob_versioning_enabled

      dynamic "delete_retention_policy" {
        for_each = (var.blob_delete_retention_days == 0 ? [] : [1])
        content {
          days = var.blob_delete_retention_days
        }
      }

      dynamic "container_delete_retention_policy" {
        for_each = (var.container_delete_retention_days == 0 ? [] : [1])
        content {
          days = var.container_delete_retention_days
        }
      }

      dynamic "cors_rule" {
        for_each = (var.blob_cors == null ? {} : var.blob_cors)
        content {
          allowed_headers    = cors_rule.value.allowed_headers
          allowed_methods    = cors_rule.value.allowed_methods
          allowed_origins    = cors_rule.value.allowed_origins
          exposed_headers    = cors_rule.value.exposed_headers
          max_age_in_seconds = cors_rule.value.max_age_in_seconds
        }
      }
    }
  }

  dynamic "static_website" {
    for_each = local.static_website_enabled
    content {
      index_document     = var.index_path
      error_404_document = var.custom_404_path
    }
  }

  network_rules {
    default_action             = var.default_network_rule
    ip_rules                   = values(var.access_list)
    virtual_network_subnet_ids = values(var.service_endpoints)
    bypass                     = var.traffic_bypass
  }
#  dynamic "network_rules" {
#    for_each = var.private_endpoint_subnet_id == null ? [] : [1]
#    content {
#      default_action = "Deny"
#    }
#  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Cannot do this until after bootstrap.
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}
#resource "azurerm_storage_container" "container" {
#  name                  = (var.name == null ? random_string.random.result : var.container_name)
#  storage_account_name  = azurerm_storage_account.sa.name
#  container_access_type = var.container_access_type
#}

resource "azurerm_private_endpoint" "state" {
#  count               = var.bootstrap_mode == "true" ? 0 : 1
  name                = "pend-${azurerm_storage_account.sa.name}"
  resource_group_name = azurerm_storage_account.sa.resource_group_name
  location            = azurerm_resource_group.state.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = azurerm_storage_account.sa.name
    private_connection_resource_id = azurerm_storage_account.sa.id
    is_manual_connection           = false

    subresource_names = ["blob"]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # DNS is configured via Azure Policy, so we don't want to fiddle with it
      private_dns_zone_group
    ]
  }
}
