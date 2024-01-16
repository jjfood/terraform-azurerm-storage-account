terraform {
  required_version = ">= 1.3.1"

  backend "azurerm" {
    use_azuread_auth = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.19.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = "1.2.23"
    }
  }
}
