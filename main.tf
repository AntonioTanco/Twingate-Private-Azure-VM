terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.85.0"
    }
    twingate = {
      source = "Twingate/twingate"
      version = "2.0.1"
    }
  }
}

provider "azurerm" {
  features {
    # Used az login in order to authenicate with my Azure Tenant
  }
}

provider "twingate" {
    #API token from Twingate
    api_token = var.tg_api_key
    #points to the network we would like to manage via Terraform
    network   = var.tg_network
}

variable "tg_api_key" {}
variable "tg_network" {}

#Creates a remote network in Twingate
resource "twingate_remote_network" "azure_private_network" {
  name = "Azure Private Network"
}

#Creates a new connector under our remote network: "azure_private_network"
resource "twingate_connector" "azure_private_connector" {
  remote_network_id = twingate_remote_network.azure_private_network.id
  status_updates_enabled = true
}

#Handles connector tokens which will be passed into our container instance as an environment varable to complete the deployment of our twingate connector
resource "twingate_connector_tokens" "twingate_connector_tokens" {
  connector_id = twingate_connector.azure_private_connector.id
}

#Creating a resource group where all of our services and components will live under
resource "azurerm_resource_group" "twingate-azure-rg" {
  name     = "zero-trust-resources"
  location = "eastus2"
}

#Creating a private virtual network under our "zero-trust-resources" resource group
resource "azurerm_virtual_network" "twingate-azure-network" {
  name                = "zero-trust-vnet"
  address_space       = ["10.16.0.0/16"]
  #pointing location to the same location as our resource group
  location            = azurerm_resource_group.twingate-azure-rg.location
  #pointing resource_group_name to the name of the newly created resource group: "zero-trust-resources"
  resource_group_name = azurerm_resource_group.twingate-azure-rg.name
}

#Creating a subnet under the "zero-trust-vnet" virtual network
resource "azurerm_subnet" "twingate-azure-container-subnet" {
  name                 = "zero-trust-twingate-subnet"
  resource_group_name  = azurerm_resource_group.twingate-azure-rg.name
  virtual_network_name = azurerm_virtual_network.twingate-azure-network.name
  address_prefixes     = ["10.16.1.0/24"]

  delegation {
    name = "delegation"

    service_delegation {
      #Delegates this subnet to Azure Container Instances
      name    = "Microsoft.ContainerInstance/containerGroups"
      #Allows for the delegated service to certain actions listed below
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"]
    }
  }
}

#Create a subnet under our Virtual Network: "twingate-azure-network" for our Linux VM
resource "azurerm_subnet" "twingate-azure-vm" {
  name                 = "zero-trust-vm-subnet"
  resource_group_name  = azurerm_resource_group.twingate-azure-rg.name
  virtual_network_name = azurerm_virtual_network.twingate-azure-network.name
  address_prefixes     = ["10.16.2.0/24"]

}

#Creates a network profile for our container instance
resource "azurerm_network_profile" "twingate_network_profile" {
  name                = "twingatenetprofile"
  location            = azurerm_resource_group.twingate-azure-rg.location
  resource_group_name = azurerm_resource_group.twingate-azure-rg.name

  container_network_interface {
    name = "twingatenic"

    ip_configuration {
      name      = "twingateipconfig"
      subnet_id = azurerm_subnet.twingate-azure-container-subnet.id
    }
  }
}

#Creates a new container instance of our Twingate Connector using the Official Twingate Connector Image under our dedicated "twingate-azure-container-subnet" subnet
resource "azurerm_container_group" "twin_connector_container" {

  name                = "twingate-azure-connector"
  location            = azurerm_resource_group.twingate-azure-rg.location
  resource_group_name = azurerm_resource_group.twingate-azure-rg.name
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.twingate-azure-container-subnet.id]
  os_type             = "Linux"

  container {
    name   = "twingateconnector"
    image  = "twingate/connector:1"
    cpu    = "1"
    memory = "1.5"
    environment_variables = {
      #passing the name of our Twingate Network
      "TWINGATE_NETWORK"          = "${var.tg_network}"
      #passing the value of our access token from our "twingate_connector_tokens"
      "TWINGATE_ACCESS_TOKEN"     = twingate_connector_tokens.twingate_connector_tokens.access_token
      #passing the value of our refresh token from our "twingate_connector_tokens"
      "TWINGATE_REFRESH_TOKEN"    = twingate_connector_tokens.twingate_connector_tokens.refresh_token
      "TWINGATE_TIMESTAMP_FORMAT" = "2"
    }
    ports {
      port     = 9999
      protocol = "UDP"
    }
  }
}

#Creating a virtual NIC for our Linux VM
resource "azurerm_network_interface" "azure_twingate_vm_nic" {
  name                = "azure-vm-nic"
  location            = azurerm_resource_group.twingate-azure-rg.location
  resource_group_name = azurerm_resource_group.twingate-azure-rg.name

  ip_configuration {
    name                          = "vmnetconfiguration"
    subnet_id                     = azurerm_subnet.twingate-azure-vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

#Creating a the Zero Trust Private Linux VM
resource "azurerm_linux_virtual_machine" "zero-trust-vm" {
  name                = "zt-private-vm"
  resource_group_name = azurerm_resource_group.twingate-azure-rg.name
  location            = azurerm_resource_group.twingate-azure-rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"

  #passing in the internal nic: "private-vm-nic"
  network_interface_ids = [azurerm_network_interface.azure_twingate_vm_nic.id]

  #Bash script which handles installing docker on the Private VM
  custom_data = base64encode(file("install-docker.sh"))

  #This SSH Key may need to be manually refreshed or reset in the Azure Portal especially if you are rebuilding the VM in Terraform
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/privatevmkey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  #Runs a local script which appends to our ~/.ssh/config file for our Remote-SSH extension
  provisioner "local-exec" {
    command = templatefile("windows-ssh-script.tpl", 
    {
      hostname = self.private_ip_address,
      user = "adminuser",
      IdentityFile = "~/.ssh/privatevmkey"
    })

    interpreter = ["Powershell", "-command" ]
  }
}

#Creates a resource group outside of the default: 'Everyone' group in Twingate that we can manually assign to the specific users we want accessing this resource
resource "twingate_group" "azure-private-vm-resource" {
  name = "Dev"
}

#Creates a resource named: "Private Azure VM" under our "Azure Private Network" with can only be accessed by the members of the "Dev Group"
resource "twingate_resource" "private_azure_vm_resource" {
  name = "Private Azure VM"
  address = azurerm_network_interface.azure_twingate_vm_nic.private_ip_address
  remote_network_id = twingate_remote_network.azure_private_network.id

  protocols = {
    allow_icmp = true
    tcp = {
      policy = "RESTRICTED"
      ports = ["80","22"]
    }
    udp = {
      policy = "ALLOW_ALL"
    }
  }
  
  access {
    group_ids = [twingate_group.azure-private-vm-resource.id]
  }
}