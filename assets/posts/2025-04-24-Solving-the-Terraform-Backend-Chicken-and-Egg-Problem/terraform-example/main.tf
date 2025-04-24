variable "environment" {
  description = "The environment to deploy to"
  type        = string
}

variable "initial_user_admin_object_id" {
  description = "The object ID of the initial user admin"
  type        = string
}

variable "subscription_id" {
  description = "The subscription ID to use"
  type        = string
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

resource "random_string" "this" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "cloudchronicles-init-rg"
  location = "polandcentral"
}

resource "azurerm_storage_account" "this" {
  name                            = "tfinitst${random_string.this.result}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
}

resource "azurerm_storage_container" "this" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.blob_data_contributor_initial_user_admin]
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "cloudchronicles-init-msi"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_federated_identity_credential" "this" {
  name                = "cloudchronicles-init-msi"
  resource_group_name = azurerm_resource_group.this.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.this.id
  subject             = "repo:krukowskid/cloudchronicles:environment:prd"
}

resource "azurerm_role_assignment" "blob_data_contributor_msi" {
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  role_definition_name             = "Storage Blob Data Contributor"
  scope                            = azurerm_storage_account.this.id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "blob_data_contributor_initial_user_admin" {
  principal_id         = var.initial_user_admin_object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.this.id
}

resource "local_file" "tfbackend" {
  content  = <<EOD
resource_group_name  = "${azurerm_resource_group.this.name}"
storage_account_name = "${azurerm_storage_account.this.name}"
container_name       = "${azurerm_storage_container.this.name}"
use_azuread_auth     = true
  EOD
  filename = "../.config/${var.environment}.tfbackend"
}

resource "local_file" "backend" {
  content  = <<EOD
terraform {
  backend "azurerm" {
    key = "init.tfstate"
  }
}
  EOD
  filename = "./backend.tf"
}
