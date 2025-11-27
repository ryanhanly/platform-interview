terraform {
  required_version = ">= 1.0.7"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }

    vault = {
      version = "3.0.1"
    }
  }
}


locals {
// Environments with Vault Details
  environments = {
    development = {
      vault_addr = "http://localhost:8201"
      vault_token = "f23612cf-824d-4206-9e94-e31a6dc8ee8d"
      network = "development"
    }
    production = {
      vault_addr = "http://localhost:8301"
      vault_token = "083672fc-4471-4ec4-9b59-a285e463a973"
      network = "production"
    }
    staging = {
      vault_addr = "http://localhost:8401"  # New port for staging Vault
      vault_token = "083672fc-4471-4ec4-9b59-a285e463a974"  # Generate a new UUID for staging
      network = "staging"
    }
  }
// Service Database Credentials
  services = {
    account = {
      data_json = jsonencode({
        db_user     = "account"
        db_password = "965d3c27-9e20-4d41-91c9-61e6631870e7"  # Keep existing; generate new for staging if needed
      })
    }
    gateway = {
      data_json = jsonencode({
        db_user     = "gateway"
        db_password = "10350819-4802-47ac-9476-6fa781e35cfd"
      })
    }
    payment = {
      data_json = jsonencode({
        db_user     = "payment"
        db_password = "a63e8938-6d49-49ea-905d-e03a683059e7"
      })
    }
  }
// Frontend Docker Images per Environment
  frontend_image = {
    development = "docker.io/nginx:latest"
    production  = "docker.io/nginx:1.22.0-alpine"
    staging     = "docker.io/nginx:1.22.0-alpine"  # Match production for staging
  }
}

// Vault Configuration for Each Environment
provider "vault" {
  for_each = local.environments
  alias    = "vault_${each.key}"
  address  = each.value.vault_addr
  token    = each.value.vault_token
}

// Vault Audit for Each Environment
resource "vault_audit" "audit" {
  for_each = local.environments
  provider = vault.vault_${each.key}
  type     = "file"
  options = {
    file_path = "/vault/logs/audit"
  }
}

//Vault Auth for Each Environment
resource "vault_auth_backend" "userpass" {
  for_each = local.environments
  provider = vault.vault_${each.key}
  type     = "userpass"
}

//Vault Secrets for Each Environment
resource "vault_generic_secret" "service_secrets" {
  for_each = {
    for pair in setproduct(keys(local.environments), keys(local.services)) : "${pair[0]}-${pair[1]}" => {
      env  = pair[0]
      svc  = pair[1]
    }
  }
  provider  = vault.vault_${each.value.env}
  path      = "secret/${each.value.env}/${each.value.svc}"
  data_json = local.services[each.value.svc].data_json
}

//Vault Policies for Each Environment
resource "vault_policy" "service_policies" {
  for_each = {
    for pair in setproduct(keys(local.environments), keys(local.services)) : "${pair[0]}-${pair[1]}" => {
      env  = pair[0]
      svc  = pair[1]
    }
  }
  provider = vault.vault_${each.value.env}
  name     = "${each.value.svc}-${each.value.env}"
  policy   = <<EOT
              path "secret/data/${each.value.env}/${each.value.svc}" {
              capabilities = ["list", "read"]
            }
            EOT
}

//Vault Service Endpoints for Each Environment
resource "vault_generic_endpoint" "service_endpoints" {
  for_each = {
    for pair in setproduct(keys(local.environments), keys(local.services)) : "${pair[0]}-${pair[1]}" => {
      env  = pair[0]
      svc  = pair[1]
    }
  }
  provider             = vault.vault_${each.value.env}
  depends_on           = [vault_auth_backend.userpass[each.value.env]]
  path                 = "auth/userpass/users/${each.value.svc}-${each.value.env}"
  ignore_absent_fields = true
  data_json = jsonencode({
    policies = ["${each.value.svc}-${each.value.env}"]
    password = "123-${each.value.svc}-${each.value.env}"
  })
}

// Docker Containers for Vault Related Services for Each Environment
resource "docker_container" "services" {
  for_each = {
    for pair in setproduct(keys(local.environments), keys(local.services)) : "${pair[0]}-${pair[1]}" => {
      env  = pair[0]
      svc  = pair[1]
    }
  }
  image = "form3tech-oss/platformtest-${each.value.svc}"
  name  = "${each.value.svc}_${each.value.env}"

  env = [
    "VAULT_ADDR=http://vault-${each.value.env}:8200",
    "VAULT_USERNAME=${each.value.svc}-${each.value.env}",
    "VAULT_PASSWORD=123-${each.value.svc}-${each.value.env}",
    "ENVIRONMENT=${each.value.env}"
  ]

  networks_advanced {
    name = local.environments[each.value.env].network
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [vault_generic_endpoint.service_endpoints["${each.value.env}-${each.value.svc}"]]
}

//Docker Containers for Frontend Service for Each Environment
resource "docker_container" "frontend" {
  for_each = local.environments
  image    = local.frontend_image[each.key]
  name     = "frontend_${each.key}"

  ports {
    internal = 80
    external = each.key == "development" ? 4080 : each.key == "production" ? 4081 : 4082  # New port for staging
  }

  networks_advanced {
    name = each.value.network
  }

  lifecycle {
    ignore_changes = all
  }
}