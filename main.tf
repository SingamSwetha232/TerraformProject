terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.68.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  features {}
}

variable "subscription_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}

resource "azurerm_resource_group" "rsc_grp" {
  name     = "hello-world-rg"
  location = "eastus"
}

resource "azurerm_key_vault" "keyvault" {
  name                = "hello-world-key-vault"
  location            = azurerm_resource_group.rsc_grp.location
  resource_group_name = azurerm_resource_group.rsc_grp.name

  sku_name  = "standard"
  tenant_id = var.tenant_id

  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  soft_delete_retention_days      = 7
  purge_protection_enabled        = false
}

resource "azurerm_virtual_network" "vnet" {
  name                = "hello-world-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rsc_grp.location
  resource_group_name = azurerm_resource_group.rsc_grp.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "hello-world-subnet"
  resource_group_name  = azurerm_resource_group.rsc_grp.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "hello-world-pip"
  location            = azurerm_resource_group.rsc_grp.location
  resource_group_name = azurerm_resource_group.rsc_grp.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  name                = "hello-world-nic"
  location            = azurerm_resource_group.rsc_grp.location
  resource_group_name = azurerm_resource_group.rsc_grp.name

  ip_configuration {
    name                          = "hello-world-config"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_virtual_machine" "vm" {
  name                  = "helloworld-vm"
  location              = azurerm_resource_group.rsc_grp.location
  resource_group_name   = azurerm_resource_group.rsc_grp.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  vm_size               = "Standard_DS2_v2"

  storage_os_disk {
    name              = "hello-world-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7_8"
    version   = "latest"
  }

  os_profile {
    computer_name  = "helloworld-vm"
    admin_username = "adminuser"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y epel-release",
      "sudo yum install -y tomcat tomcat-webapps tomcat-admin-webapps",
      "sudo systemctl start tomcat",
      "sudo systemctl enable tomcat"
    ]

    connection {
      host     = azurerm_public_ip.public_ip.ip_address
      type     = "ssh"
      user     = "adminuser"
      password = "Password1234!"
      agent    = false
      timeout  = "5m"
    }
  }
}

resource "azurerm_key_vault_key" "keyvault_key" {
  name         = "hello-world-key"
  key_vault_id = azurerm_key_vault.keyvault.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["decrypt", "encrypt", "sign", "verify"]
}

resource "azurerm_storage_account" "storage" {
  name                     = "helloworldstorage${random_string.random_suffix.result}"
  resource_group_name      = azurerm_resource_group.rsc_grp.name
  location                 = azurerm_resource_group.rsc_grp.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "random_string" "random_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_private_dns_zone" "dns" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rsc_grp.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "hello-world-link"
  resource_group_name   = azurerm_resource_group.rsc_grp.name
  private_dns_zone_name = azurerm_private_dns_zone.dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "endpoint" {
  name                = "hello-world-endpoint"
  location            = azurerm_resource_group.rsc_grp.location
  resource_group_name = azurerm_resource_group.rsc_grp.name
  subnet_id           = azurerm_subnet.subnet.id
  private_service_connection {
    name                           = "hello-world-connection"
    private_connection_resource_id = azurerm_storage_account.storage.id
    subresource_names              = ["blob"]
    is_manual_connection           = true
    request_message = jsonencode({
      description = "Connection to Azure Storage Account",
    })
  }
}
