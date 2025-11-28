terraform {
  required_version = ">= 1.0.7"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.0.1"
    }
  }
}

provider "vault" {
  alias   = "dev_vault"
  address = "http://localhost:8201"
  token   = "f23612cf-824d-4206-9e94-e31a6dc8ee8d"
}

provider "vault" {
  alias   = "prod_vault"
  address = "http://localhost:8301"
  token   = "083672fc-4471-4ec4-9b59-a285e463a973"
}

provider "vault" {
  alias   = "stag_vault"
  address = "http://localhost:8401"
  token   = "083672fc-4471-4ec4-9b59-a285e463a974"
}

locals {
  environments = {
    development = { network = "development" }
    production  = { network = "production" }
    staging     = { network = "staging" }
  }

  services = {
    account = {
      data_json = jsonencode({
        db_user = "account",
        db_password = "965d3c27-9e20-4d41-91c9-61e6631870e7" }) }
    gateway = {
      data_json = jsonencode({
        db_user = "gateway",
        db_password = "10350819-4802-47ac-9476-6fa781e35cfd" }) }
    payment = {
      data_json = jsonencode({
        db_user = "payment",
        db_password = "a63e8938-6d49-49ea-905d-e03a683059e7" }) }
  }

  frontend_image = {
    development = "docker.io/nginx:latest"
    production  = "docker.io/nginx:1.22.0-alpine"
    staging     = "docker.io/nginx:1.22.0-alpine"
  }
}

module "development" {
  source         = "./modules/environment"
  environment    = "development"
  vault_addr     = "http://localhost:8201"
  vault_token    = "f23612cf-824d-4206-9e94-e31a6dc8ee8d"
  services       = local.services
  frontend_image = local.frontend_image.development
  external_port  = 4080
}

module "production" {
  source         = "./modules/environment"
  environment    = "production"
  vault_addr     = "http://localhost:8301"
  vault_token    = "083672fc-4471-4ec4-9b59-a285e463a973"
  services       = local.services
  frontend_image = local.frontend_image.production
  external_port  = 4081
}

module "staging" {
  source         = "./modules/environment"
  environment    = "staging"
  vault_addr     = "http://localhost:8401"
  vault_token    = "083672fc-4471-4ec4-9b59-a285e463a974"
  services       = local.services
  frontend_image = local.frontend_image.staging
  external_port  = 4082
}