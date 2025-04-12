terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    databricks = {
      source = "databricks/databricks"
    }
  }
}

provider "databricks" {
  alias      = "azure_account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.account_id
  auth_type  = "azure-cli"
}


provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

data "azurerm_resource_group" "this" {
  name = var.resource_group
}

data "azurerm_databricks_workspace" "this" {
  name                = var.databricks_workspace_name
  resource_group_name = var.resource_group
}

locals {
  databricks_workspace_host = data.azurerm_databricks_workspace.this.workspace_url
  databricks_workspace_id   = data.azurerm_databricks_workspace.this.workspace_id
  prefix                    = var.prefix
}

provider "databricks" {
  host = local.databricks_workspace_host
}

// Create azure managed identity for Unity Catalog
resource "azurerm_databricks_access_connector" "unity" {
  name                = "${local.prefix}-databricks-mi"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  identity {
    type = "SystemAssigned"
  }
}

// Create a storage account for Unity Catalog
resource "azurerm_storage_account" "unity_catalog" {
  name                     = "${local.prefix}storageaccuc"
  resource_group_name      = data.azurerm_resource_group.this.name
  location                 = data.azurerm_resource_group.this.location
  tags                     = data.azurerm_resource_group.this.tags
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
}

// Create a container in the storage account
resource "azurerm_storage_container" "unity_catalog" {
  name                  = "${local.prefix}-container"
  storage_account_name  = azurerm_storage_account.unity_catalog.name
  container_access_type = "private"
}

// Assign role to the managed identity
resource "azurerm_role_assignment" "mi_data_contributor" {
  scope                = azurerm_storage_account.unity_catalog.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.unity.identity[0].principal_id
}

// Create the Unity Catalog metastore
resource "databricks_metastore" "techgen_metastore" {
  name         = "techgen_metastore"
  storage_root = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.unity_catalog.name,
    azurerm_storage_account.unity_catalog.name
  )
  force_destroy = true
  owner         = "account_unity_admin" # Ensure this principal exists
}

// Assign the managed identity to the metastore
resource "databricks_metastore_data_access" "first" {
  metastore_id = databricks_metastore.techgen_metastore.id
  name         = "metastore-key"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.unity.id
  }
  is_default = true
}

// Attach the Databricks workspace to the metastore
resource "databricks_metastore_assignment" "this" {
  workspace_id         = local.databricks_workspace_id
  metastore_id         = databricks_metastore.techgen_metastore.id
  default_catalog_name = "pnd_catalog"
}

// Create a new catalog in the metastore
resource "databricks_catalog" "pnd_catalog" {
  name         = "pnd_catalog"
  comment      = "Catalog for PND use cases"
  owner        = "account_unity_admin"
  force_destroy = true
}

// Create schemas for bronze, silver, and gold layers
resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.pnd_catalog.name
  name         = "bronze"
  comment      = "Schema for bronze layer"
  owner        = "account_unity_admin"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.pnd_catalog.name
  name         = "silver"
  comment      = "Schema for silver layer"
  owner        = "account_unity_admin"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.pnd_catalog.name
  name         = "gold"
  comment      = "Schema for gold layer"
  owner        = "account_unity_admin"
}

// Grant permissions to the metastore
resource "databricks_grants" "metastore_admin" {
  metastore = databricks_metastore.techgen_metastore.name

  grant {
    principal  = "account_unity_admin" # Replace with a valid admin user/group
    privileges = [
      "CREATE CATALOG",
      "CREATE EXTERNAL LOCATION",
      "CREATE MANAGED STORAGE",
      "CREATE SCHEMA"
    ]
  }
}

// Grant schema-level permissions
resource "databricks_grants" "bronze_schema" {
  schema = databricks_schema.bronze.name

  grant {
    principal  = "data_engineer"
    privileges = ["CREATE_TABLE", "SELECT", "USE_SCHEMA"]
  }
}

resource "databricks_grants" "silver_schema" {
  schema = databricks_schema.silver.name

  grant {
    principal  = "data_engineer"
    privileges = ["CREATE_TABLE", "SELECT", "USE_SCHEMA"]
  }
}

resource "databricks_grants" "gold_schema" {
  schema = databricks_schema.gold.name

  grant {
    principal  = "data_engineer"
    privileges = ["CREATE_TABLE", "SELECT", "USE_SCHEMA"]
  }
}

