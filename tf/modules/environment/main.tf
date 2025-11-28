# tf/modules/environment/main.tf
terraform {
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

variable "environment" {
  type = string
}

variable "vault_addr" {
  type = string
}

variable "vault_token" {
  type = string
}

variable "services" {
  type = map(object({
    data_json = string
  }))
}

variable "frontend_image" {
  type = string
}

variable "external_port" {
  type = number
}

provider "vault" {
  alias   = "env_vault"
  address = var.vault_addr
  token   = var.vault_token
}

resource "vault_audit" "audit" {
  provider = vault.env_vault
  type     = "file"
  options = {
    file_path = "/vault/logs/audit"
  }
}

resource "vault_auth_backend" "userpass" {
  provider = vault.env_vault
  type     = "userpass"
}

resource "vault_generic_secret" "secrets" {
  for_each  = var.services
  provider  = vault.env_vault
  path      = "secret/${var.environment}/${each.key}"
  data_json = each.value.data_json
}

resource "vault_policy" "policies" {
  for_each = var.services
  provider = vault.env_vault
  name     = "${each.key}-${var.environment}"
  policy   = <<EOT
path "secret/data/${var.environment}/${each.key}" {
    capabilities = ["list", "read"]
}
EOT
}

resource "vault_generic_endpoint" "endpoints" {
  for_each = var.services
  provider = vault.env_vault
  path     = "auth/userpass/users/${each.key}-${var.environment}"
  ignore_absent_fields = true
  data_json = jsonencode({
    policies = ["${each.key}-${var.environment}"]
    password = "123-${each.key}-${var.environment}"
  })
  depends_on = [vault_auth_backend.userpass]
}

resource "docker_network" "network" {
  name = var.environment
}

resource "docker_container" "services" {
  for_each = var.services
  image    = "form3tech-oss/platformtest-${each.key}"
  name     = "${each.key}_${var.environment}"
  env = [
    "VAULT_ADDR=http://vault-${var.environment}:8200",
    "VAULT_USERNAME=${each.key}-${var.environment}",
    "VAULT_PASSWORD=123-${each.key}-${var.environment}",
    "ENVIRONMENT=${var.environment}"
  ]
  networks_advanced {
    name = docker_network.network.name
  }
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "frontend" {
  image = var.frontend_image
  name  = "frontend_${var.environment}"
  ports {
    internal = 80
    external = var.external_port
  }
  networks_advanced {
    name = docker_network.network.name
  }
  lifecycle {
    ignore_changes = all
  }
}