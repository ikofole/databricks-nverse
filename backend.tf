terraform {
  backend "azurerm" {
    resource_group_name  = "Data_EngineerRG"           # Your resource group
    storage_account_name = "degroup1"                  # Your storage account name
    container_name       = "pnd-container"             # Your blob container name
    key                  = "databricks-bundle.tfstate" # State file name
  }
}


