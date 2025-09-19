data "azurerm_client_config" "current" {}

# Resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg"
  location = var.location
}

resource "azurerm_network_security_group" "nsg" {
  name                = "managed-identity-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
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

resource "azurerm_public_ip" "public_ip" {
  name                = "vm-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
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
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_nic" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Managed Identity
resource "azurerm_user_assigned_identity" "cosmos_identity" {
  name                = "cosmos-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_cosmosdb_sql_role_definition" "cosmos_sql_role_definition" {
  name                = "examplesqlroledef"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.cosmos.id]

  permissions {
    data_actions = [
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/read",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/delete",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/replace",
      # "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/executeQuery"
    ]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_role_assignment" {
  name                = uuid()
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.cosmos_sql_role_definition.id
  principal_id        = azurerm_user_assigned_identity.cosmos_identity.principal_id
  scope               = azurerm_cosmosdb_account.cosmos.id
}

# VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1ms"
  admin_username      = "madmax"

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
              # Installing Nginx and Node.js
              cd /home/madmax
              apt-get update -y
              apt-get install -y nginx
              echo "Hello from Azure VM with NGINX!" > /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
              sudo bash nodesource_setup.sh
              sudo apt install nodejs -y
              # Installing PM2
              sudo npm i -g pm2              
              
              cat >> index.js << EOL
              require("dotenv").config();
              const { DefaultAzureCredential, ManagedIdentityCredential } = require("@azure/identity");
              const express = require("express");
              const bodyParser = require("body-parser");
              const { CosmosClient } = require("@azure/cosmos");
              const credential = new DefaultAzureCredential();
              const app = express();
              app.use(bodyParser.json());

              // Cosmos DB setup
              const client = new CosmosClient({
                endpoint: process.env.COSMOS_ENDPOINT,
                aadCredentials: credential
              });
              const database = client.database(process.env.COSMOS_DATABASE);
              const container = database.container(process.env.COSMOS_CONTAINER);

              // CREATE
              app.post("/items", async (req, res) => {
                try {
                  const { resource } = await container.items.create(req.body);
                  res.status(201).json(resource);
                } catch (err) {
                  res.status(500).json({ error: err.message });
                }
              });

              // READ ALL
              app.get("/items", async (req, res) => {
                try {
                  const { resources } = await container.items.readAll().fetchAll();
                  res.json(resources);
                } catch (err) {
                  res.status(500).json({ error: err.message });
                }
              });

              // READ ONE
              app.get("/items/:id", async (req, res) => {
                try {
                  const { resource } = await container.item(req.params.id, req.params.id).read();
                  res.json(resource);
                } catch (err) {
                  res.status(404).json({ error: "Item not found" });
                }
              });

              // UPDATE
              app.put("/items/:id", async (req, res) => {
                try {
                  const updatedItem = { ...req.body, id: req.params.id };
                  const { resource } = await container.items.upsert(updatedItem);
                  res.json(resource);
                } catch (err) {
                  res.status(500).json({ error: err.message });
                }
              });

              // DELETE
              app.delete("/items/:id", async (req, res) => {
                try {
                  await container.item(req.params.id, req.params.id).delete();
                  res.json({ status: "deleted" });
                } catch (err) {
                  res.status(404).json({ error: "Item not found" });
                }
              });

              const PORT = 8080;
              app.listen(PORT, () => console.log(`🚀 Server running on port 8080`));
              EOL
              
              cat >> package.json << EOP
              {
                "name": "azure-function-app-cosmos",
                "version": "1.0.0",
                "main": "index.js",
                "scripts": {
                  "test": "echo \"Error: no test specified\" && exit 1"
                },
                "keywords": [],
                "author": "",
                "license": "ISC",
                "description": "",
                "dependencies": {
                  "@azure/cosmos": "^4.5.0",
                  "@azure/identity": "^4.11.1",
                  "body-parser": "^2.2.0",
                  "dotenv": "^17.2.1",
                  "express": "^5.1.0"
                }
              }
              EOP

              cat >> .env << EOC 
              COSMOS_ENDPOINT=https://madmaxcosmos.documents.azure.com:443/
              COSMOS_DATABASE=db
              COSMOS_CONTAINER=users
              PORT=8080
              EOC
              cat > /etc/nginx/sites-available/default << EONG
              server {
                  listen 80;
                  server_name _;

                  location / {
                      proxy_pass http://127.0.0.1:8080;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade \$http_upgrade;
                      proxy_set_header Connection 'upgrade';
                      proxy_set_header Host \$host;
                      proxy_cache_bypass \$http_upgrade;
                  }
              }
              EONG
              systemctl restart nginx
                            
              npm install
              pm2 start index.js
              EOF              
  )
}

# CosmosDB Account
resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "madmaxcosmos"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Strong"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "database" {
  name                = "db"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "contaienr" {
  name                  = "container"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.database.name
  partition_key_paths   = ["/id"]
  partition_key_version = 1
  throughput            = 400
}