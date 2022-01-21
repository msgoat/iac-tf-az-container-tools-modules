terraform {
  required_providers {
    azurerm = {
      version = "~> 2.85"
    }
    helm = {
      version = "~> 2.1"
    }
    kubernetes = {
      version = "~> 2.1"
    }
  }
}

locals {
  module_common_tags = var.common_tags
}
