variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group" {
  description = "Azure resource group name"
  type        = string
}

variable "databricks_workspace_name" {
  description = "Databricks workspace name"
  type        = string
}

variable "account_id" {
  description = "Databricks account ID"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "aad_groups" {
  description = "List of Azure AD groups for Databricks"
  type        = list(string)
}


