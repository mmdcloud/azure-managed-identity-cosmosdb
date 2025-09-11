# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg"
  location = var.location
}

# VNet + Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network interface
resource "azurerm_network_interface" "nic" {
  name                = "nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Managed Identity
resource "azurerm_user_assigned_identity" "cosmos_identity" {
  name                = "cosmos-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_role_assignment" {
  name                = "cosmosdb-role-assignment"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = "00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.cosmos_identity.principal_id
  scope               = "/"
}

# VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-sample"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1ms"
  admin_username      = "azureuser"

  network_interface_ids           = [azurerm_network_interface.nic.id]
  admin_password                  = "Mohitdixit12345!"
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cosmos_identity.id]
  }

  custom_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx
              echo "Hello from Azure VM with NGINX!" > /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF
  )
}

# CosmosDB Account
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmosacct${random_string.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableVnetServiceEndpoint"
  }
}