provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mediawiki_rg" {
  name     = "mediawiki-rg"
  location = "eastus"
}

resource "azurerm_mysql_server" "mediawiki_mysql_server" {
  name                = "mediawiki-mysql-server"
  location            = azurerm_resource_group.mediawiki_rg.location
  resource_group_name = azurerm_resource_group.mediawiki_rg.name
  sku_name            = "B_Gen5_1"
  storage_profile {
    storage_mb        = 5120
    backup_retention_days = 7
    geo_redundant_backup_enabled = false
  }
  administrator_login          = "mediawikiadmin"
  administrator_login_password = "password123!"
  version                       = "5.7"
}

resource "azurerm_container_registry" "mediawiki_container_registry" {
  name                = "mediawiki-container-registry"
  location            = azurerm_resource_group.mediawiki_rg.location
  resource_group_name = azurerm_resource_group.mediawiki_rg.name
  sku                 = "Standard"
}

resource "azurerm_kubernetes_cluster" "mediawiki_k8s_cluster" {
  name                = "mediawiki-k8s-cluster"
  location            = azurerm_resource_group.mediawiki_rg.location
  resource_group_name = azurerm_resource_group.mediawiki_rg.name
  dns_prefix          = "mediawiki-k8s"
  linux_profile {
    admin_username = "mediawikiadmin"
    ssh_key {
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDXaDRq3FkSKHh8xOdyg/HOTzB2+h1
      ...
      ...
    }
  }

  agent_pool_profile {
    name            = "mediawiki-agent-pool"
    count           = 1
    vm_size         = "Standard_D2s_v3"
    os_disk_size_gb = 30
    os_type         = "Linux"
  }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }

  role_based_access_control {
    enabled = true
  }
}

data "azurerm_container_registry" "mediawiki_container_registry" {
  name                = azurerm_container_registry.mediawiki_container_registry.name
  resource_group_name = azurerm_resource_group.mediawiki_rg.name
}

resource "kubernetes_namespace" "mediawiki_namespace" {
  metadata {
    name = "mediawiki"
  }
}

resource "kubernetes_secret" "mysql_secret" {
  metadata {
    name      = "mysql-secret"
    namespace = kubernetes_namespace.mediawiki_namespace.metadata.0.name
  }

  data = {
    password = base64encode(azurerm_mysql_server.mediawiki_mysql_server.administrator_login_password)
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "mediawiki_deployment" {
  metadata {
    name      = "mediawiki"
    namespace = kubernetes_namespace.mediawiki_namespace.metadata.0.name

    labels = {
      app = "mediawiki"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mediawiki"
      }
    }

    template {
      metadata
{
labels = {
app = "mediawiki"
}
}
  spec {
    container {
      name  = "mediawiki"
      image = "${azurerm_container_registry.mediawiki_container_registry.login_server}/mediawiki:${var.mediawiki_version}"
      env {
        name  = "MW_DB_HOST"
        value = "${azurerm_mysql_server.mediawiki_mysql_server.fqdn}"
      }
      env {
        name  = "MW_DB_USER"
        value = "${azurerm_mysql_server.mediawiki_mysql_server.administrator_login}@${azurerm_mysql_server.mediawiki_mysql_server.name}"
      }
      env {
        name      = "MW_DB_PASSWORD"
        valueFrom = {
          secretKeyRef = {
            name = kubernetes_secret.mysql_secret.metadata.0.name
            key  = "password"
          }
        }
      }
      port {
        name       = "http"
        container_port = 80
      }
    }
  }
}
}
}

resource "kubernetes_service" "mediawiki_service" {
metadata {
name = "mediawiki"
namespace = kubernetes_namespace.mediawiki_namespace.metadata.0.name
}

spec {
selector = {
app = "mediawiki"
}
port {
  name       = "http"
  port       = 80
  target_port = "http"
}

type = "LoadBalancer"
}
}
