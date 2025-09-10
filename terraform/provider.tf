terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = "ac0192a4-f2ec-4c2e-bf7e-6e8a051fe856"
  features {
    subscription {
      prevent_cancellation_on_destroy = true
    }
  }
}