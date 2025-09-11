provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

resource "random_string" "this" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-demo-${random_string.this.result}"
  location = "polandcentral"
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-demo-${random_string.this.result}"
  location                      = "polandcentral"
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  rbac_authorization_enabled    = true

  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-demo-${random_string.this.result}"
  location            = "polandcentral"
  resource_group_name = "dns-demo-prd"

  subnet_id = var.subnet_id

  private_service_connection {
    name                           = "psc-demo-${random_string.this.result}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "demo-dns-zone-group-${random_string.this.result}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

module "wait_for_dns" {
  source = "../wait_for_dns"

  triggers = {
    ip = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
  }
  dns_name   = azurerm_key_vault.this.vault_uri
  ip_address = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

resource "azurerm_key_vault_secret" "this" {
  name         = "example-secret"
  value        = "example-value"
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [module.wait_for_dns]
}
