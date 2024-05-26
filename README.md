<h1>🛑Zero Trust Azure Dev Environment</h1>

<h3>Project Overview</h3>
<p>Used Terraform to automate the deployment of the Twingate Connector and Private Linux VM to Azure in order to create a Zero Trust VM that can only be accessed via authenicating the Twingate Client assuming you are apart of of the "Dev" group. Terraform was used to interact with my Azure tenant to create the necessary resource group, vNET & subnets, Network security group, virtual NIC, Private Linux VM and ulimately automate the entire deployment of the Twingate Connector.</p>

<h4>Language/Software Used</h4>
<a href=https://developer.hashicorp.com/terraform/install>Terraform v1.6.6</a></br>
Visual Studio Code (<a href=https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh>Remote-SSH Extension Installed</a>) </br>
<a href=https://www.twingate.com/download>Twingate Client</a>

<h4>Prerequisite</h4>

+ Azure account is needed, you can get a free trial @ https://azure.microsoft.com/en-us/pricing/offers/ms-azr-0044p </br>

+ Twingate account is needed, you can create an account @ https://auth.twingate.com/</br>

+ You will need to generate an API Key within the Twingate Admin Portal, this was referenced in the main.tf file which was passed in via a .tfvars file. 

___

> [!CAUTION]
> Never modify any production environment you don't own unless you have explicit permission or reason to do so. This repo isn't to be used as a guide but rather a showcasing of my personal use case of my Azure Tenant and Twingate to further secure my Dev environment that was created in this repo @ <a href=https://github.com/AntonioTanco/Terraform-Dev-Environment---Azure>Azure Dev Environment</a> 

<h3>Understanding Twingate</h3>

<p>Twingate is a modern day VPN alternative to Traditional VPN's which allows us to create and establish secure connections via the Twingate Client to only resources we are permitted to access, no matter if that resource is located on-prem or in the cloud. Twingate is built on Zero Trust Network Architecture Principles which allows me to easily access the Private Linux VM only after authenicating with the Twingate Client and being apart of the correct access group.</p>

<h3>Why Twingate</h3>

<p>Going from a Public to Private Dev environments has a lot of benefits but one of the biggest reasons for my personal implementation of Twingate would be to segregate my Dev Environment in the event my personal computer was accessed unknowly, left awake, compromised, etc... This offers a bit of piece of mind as something as simple as me playing with a metered API Service or metered VPS can turn into a huge bill if a bunch of compute or request were made unknowly.

You can learn more about Twingate and it's use cases here @ https://www.twingate.com/docs</p>

<h3>Understanding Main.TF</h3>
<p>Twingate has a very detailed guide of deploying the Twingate Connector to Azure, I recommend reading that guide through before attempting to deploy this in Azure for the sake of understanding. 

https://www.twingate.com/docs/terraform-azure</p>

<h4>Creating The Twingate Network and Connector</h4>
<p>As I mentioned eariler within this repo you will need an API Key which in my case was stored in a seperate .tfvars file and passed into main.tf. You must be an admin in order to generate an API Token. The name of my network was also passed in via this .tfvars file, it might be weird to see <i>network</i> twice; but the <i>remote network</i> refers to the actual name of the location which your <i>twingate resource</i> lives in; While <i>network</i> refers to the domain name of your <b>Twingate Tenant: {<i>network</i>}.twingate.com</b></p>

```
#main.TF

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
```
<h4>Building out the Azure Infrastructure - Twingate Connector</h4>
<p>In this portion of <b>main.tf</b>, I created the neccesary resource group, vNET, Two Subnets, network profile and container service which is where the twingate connector will be deployed via Docker.

Requirements for Twingate Connector Deployment:
+ A dedicated subnet under the same virtual network where the virtual machine will live is required. This is the reason why two subnets were created under the <i>zero-trust-vnet</i> and why there were addressed with 10.16.0.0/16</p>
+ The Twingate <i>network</i> is passed into the <i>twin_connector_container</i> including the <i>subnet_ids</i> of the subnet <i>twingate-azure-container-subnet</i> we created eariler
+ The <i>access/refresh</i> tokens were declared eariler for this reason as well as this is needed for the build out of the Twingate Connector container as well.

```
#main.TF

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
```

<h4>Building out the Azure Infrastructure - Private Linux VM</h4>
<p>Just like any other build out you will need a virtual NIC to attach to the VM during provisioning. Nothing changed in terms of local-exec for me as I always want to append this information in the case of a rebuild without needing to write that information myself.

NOTE:
+ You may notice I passed in a custom script upon building the VM, this is because I want my VM to have Docker installed but realistically this script can contain anything you want.</p>

```
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
```

<h4>Building out the Azure Infrastructure - Finishing Touches</h4>
<p>As a mentioned in the project overview, you must be apart of the "Dev" group in order to access this virtual machine. Here is where I created that group programmatically and where I also created the actually <b>resource (zero-trust vm)</b> under the <b>remote network (Azure Private Network)</b> I declared earlier.

NOTE:
+ It is also possible to create a static or dynamic security policy which can be passed to any twingate resource you've declared but for my use case this wasn't implemented. If you would like to do so for yourself you my reference the Terraform Docs here @ https://registry.terraform.io/providers/Twingate/twingate/latest/docs/resources/resource </p>

```
#Creates a resource group outside of the default: 'Everyone' group in Twingate that we can manually assign to the specific users we want accessing this resource
resource "twingate_group" "azure-private-vm-resource" {
  name = "Dev"
}

#Creates a resource named: "Private Azure VM" under our "Azure Private Network" which can only be accessed by the members of the "Dev Group"
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
```



