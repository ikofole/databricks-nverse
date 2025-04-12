output "access_connector_principal_id" {
  value = azurerm_databricks_access_connector.unity.identity[0].principal_id
}
