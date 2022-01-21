terraform {
  required_providers {
    azurerm = {
      version = "~> 2.70"
    }
    helm = {
      version = "~> 2.1"
    }
    kubernetes = {
      version = "~> 2.1"
    }
    random = {
      version = "~> 3.0"
    }
  }
}

locals {
  module_common_tags = var.common_tags
}
