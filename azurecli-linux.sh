az login
az account set --subscription XXXXXXXXXXXXXXXXXXXXXX

export APP_PE_DEMO_RG=nz007lin-pedemo-rg
export LOCATION=eastus  
export DEMO_VNET=nz007lin-pedemo-vnet
export DEMO_VNET_CIDR=10.0.0.0/16
export DEMO_VNET_APP_SUBNET=app_subnet
export DEMO_VNET_APP_SUBNET_CIDR=10.0.1.0/24
export DEMO_VNET_PL_SUBNET=pl_subnet
export DEMO_VNET_PL_SUBNET_CIDR=10.0.2.0/24

export DEMO_APP_PLAN=nz007lin-app-plan
export DEMO_APP_NAME=nz007lin-simplejava-app

export DEMO_APP_VM=pldemovm
export DEMO_APP_VM_ADMIN=azureuser
export DEMO_VM_IMAGE=MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest
export DEMO_VM_SIZE=Standard_DS2_v2
export DEMO_APP_KV=nz007lin-demo-kv-01

export KV_SECRET_APP_MESSAGE="APP-MESSAGE"
export KV_SECRET_APP_MESSAGE_VALUE="This is a test app message"
export KV_SECRET_APP_MESSAGE_VAR="APP_MESSAGE"
export KV_SECRET_APP_KV_NAME_VAR="KV_NAME"

# Create Resource Group
az group create -l $LOCATION -n $APP_PE_DEMO_RG

# Create VNET and App Service delegated Subnet
az network vnet create -g $APP_PE_DEMO_RG -n $DEMO_VNET --address-prefix $DEMO_VNET_CIDR \
 --subnet-name $DEMO_VNET_APP_SUBNET --subnet-prefix $DEMO_VNET_APP_SUBNET_CIDR

# Create Subnet to create PL, VMs etc.
az network vnet subnet create -g $APP_PE_DEMO_RG --vnet-name $DEMO_VNET -n $DEMO_VNET_PL_SUBNET \
    --address-prefixes $DEMO_VNET_PL_SUBNET_CIDR

# Create VM to host
# - DNS
# - Java
# - VS Code
# - Azure CLI
# - Maven
az vm create -n $DEMO_APP_VM -g $APP_PE_DEMO_RG --image MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest \
    --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET --public-ip-sku Standard --size $DEMO_VM_SIZE --admin-username $DEMO_APP_VM_ADMIN

# Capture public IP of the jump/DNS box
# 52.188.33.128

# Install VS Code - https://code.visualstudio.com/download
# Install NodeJS and NPM- https://nodejs.org/en/download
# Install Azure CLI - https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest
# Setup DNS server
# Windows DNS Server - https://www.wintelpro.com/install-and-configure-dns-on-windows-server-2019/


################ Complete the VM Setup before moving next #######################
# Create App Service Plan
az appservice plan create -g $APP_PE_DEMO_RG -l $LOCATION -n $DEMO_APP_PLAN \
   --is-linux --number-of-workers 1 --sku P1V2

# Create Node JS Web App
az webapp create -g $APP_PE_DEMO_RG -p $DEMO_APP_PLAN -n $DEMO_APP_NAME --runtime "NODE|10-lts"

# "enabledHostNames": [
#    "nz007lin-simplejava-app.azurewebsites.net",
#    "nz007lin-simplejava-app.scm.azurewebsites.net"
#  ]

# "outboundIpAddresses": "168.62.51.220,13.92.179.222,52.168.2.55,13.92.181.253,168.62.180.253",
# "possibleOutboundIpAddresses": "40.71.11.143,40.117.230.15,104.211.5.249,168.62.181.40,52.168.3.5,168.62.51.220,13.92.179.222,52.168.2.55,13.92.181.253,168.62.180.253",

# Assign MSI for Java Web App
# Please save the output and take a note of the ObjecID and save it as $APP_MSI
az webapp identity assign -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME

# Capture identity from output
export APP_MSI="6c44a847-c59b-4b5b-91ae-307df62f8bf4"

# Create Key Vault
az keyvault create --location $LOCATION --name $DEMO_APP_KV --resource-group $APP_PE_DEMO_RG

export KV_URI="/subscriptions/03228871-7f68-4594-b208-2d8207a65428/resourceGroups/nz007lin-pedemo-rg/providers/Microsoft.KeyVault/vaults/nz007lin-linux-demo-kv-01"
# Set Key Vault Secrets
# Please  take a note of the Secret Full Path and save it as KV_SECRET_DB_UID_FULLPATH
az keyvault secret set --vault-name $DEMO_APP_KV --name "$KV_SECRET_APP_MESSAGE" --value "$KV_SECRET_APP_MESSAGE_VALUE"

# Set Policy for Web App to access secrets
az keyvault set-policy --name $DEMO_APP_KV  --resource-group $APP_PE_DEMO_RG --object-id $APP_MSI --secret-permissions get list

# Set Private DNS Zone Settings
az webapp config appsettings set -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --settings "WEBSITE_DNS_SERVER"="168.63.129.16"
az webapp config appsettings set -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --settings "WEBSITE_VNET_ROUTE_ALL"="1"

# Create Web App variable
az webapp config appsettings set -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --settings $KV_SECRET_APP_MESSAGE_VAR="$KV_SECRET_APP_MESSAGE"
az webapp config appsettings set -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --settings $KV_SECRET_APP_KV_NAME_VAR="$DEMO_APP_KV"

#
# Create Private Links
#
# Prepare the Subnet
az network vnet subnet update -g $APP_PE_DEMO_RG -n $DEMO_VNET_PL_SUBNET --vnet-name $DEMO_VNET --disable-private-endpoint-network-policies
az network vnet subnet update -g $APP_PE_DEMO_RG -n $DEMO_VNET_PL_SUBNET --vnet-name $DEMO_VNET --disable-private-link-service-network-policies

# Create Key Vault Private Link
# Get the Resource ID of the Key Vault from the Portal, assign it to KV_RESOURCE_ID and create private link
az network private-endpoint create -g $APP_PE_DEMO_RG -n kvpe --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET \
    --private-connection-resource-id "$KV_URI" --connection-name kvpeconn -l $LOCATION --group-id "vault"

export PRIVATE_KV_IP="10.0.2.4"
export AZUREKEYVAULT_ZONE=privatelink.vaultcore.azure.net
az network private-dns zone create -g $APP_PE_DEMO_RG -n $AZUREKEYVAULT_ZONE
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREKEYVAULT_ZONE -n $DEMO_APP_KV -a $PRIVATE_KV_IP
az network private-dns link vnet create -g $APP_PE_DEMO_RG --virtual-network $DEMO_VNET --zone-name privatelink.vaultcore.azure.net --name kvdnsLink --registration-enabled true

# Creating Forward Lookup Zones in the DNS server you created above
#   Create the zone for: vault.azure.net
#       Create an A Record for the Key Vault with the name and its private endpoint address

# Creating Forward Lookup Zones in the DNS server you created above
# You may be using root hints for DNS resolution on your custom DNS server.
# Please add 168.63.129.16 as default forwarder on you custom DNS server.
# https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverforwarder?view=win10-ps

#   Create the zone for: vault.azure.net
#       Create an A Record for the Key Vault with the name and its private endpoint address
# Switch to custom DNS on VNET
# export DEMO_APP_VM_IP="10.0.2.4"
# az network vnet update -g $APP_PE_DEMO_RG -n $DEMO_VNET --dns-servers $DEMO_APP_VM_IP

#
# Change KV firewall - allow only PE access
# Verify it's locked down (click on Secrets from browser)
#

# Attach Web App to the VNET (VNET integration)
az webapp vnet-integration add -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --vnet $DEMO_VNET --subnet $DEMO_VNET_APP_SUBNET

# Now restart the webapp
az webapp restart -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME
# ...and verify it still has access to KV

#######################################################################################
# Stop here to test Web App's VNET Integration 
#######################################################################################

# Get the webapp resource id
az webapp show -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME

export WEB_APP_RESOURCE_ID="/subscriptions/fbd6916d-a76d-48f0-9b03-f1d9610d7970/resourceGroups/nz007lin-pedemo-rg/providers/Microsoft.Web/sites/nz007lin-simplejava-app"

# Create Web App Private Link
az network private-endpoint create -g $APP_PE_DEMO_RG -n webpe --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET \
    --private-connection-resource-id $WEB_APP_RESOURCE_ID --connection-name webpeconn -l $LOCATION --group-id "sites"

# The remaining private DNS for app's frontend can be handled via private DNS zones
export PRIVATE_APP_IP=""

export AZUREWEBSITES_ZONE=azurewebsites.net
az network private-dns zone create -g $APP_PE_DEMO_RG -n $AZUREWEBSITES_ZONE
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREWEBSITES_ZONE -n $DEMO_APP_NAME -a $PRIVATE_APP_IP

export AZUREWEBSITES_SCM_ZONE=scm.azurewebsites.net
az network private-dns zone create -g $APP_PE_DEMO_RG -n $AZUREWEBSITES_SCM_ZONE
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREWEBSITES_SCM_ZONE -n $DEMO_APP_NAME -a $PRIVATE_APP_IP

# Link zones to VNET
az network private-dns link vnet create -g $APP_PE_DEMO_RG -n webpe-link -z $AZUREWEBSITES_ZONE -v $DEMO_VNET -e False
az network private-dns link vnet create -g $APP_PE_DEMO_RG -n webpe-link -z $AZUREWEBSITES_SCM_ZONE -v $DEMO_VNET -e False

# Create remaining DNS entries (app's frontend)
#   Create the zone for: azurewebsites.net
#       Create an A Record for the Web App with the name and its private endpoint address
#   Create the zone for: scm.azurewebsites.net
#       Create an A Record for the Web App SCM with the name and its private endpoint address


# Create Web App Private Link
# Get the Resource ID of the Web App from the Portal, assign it to WEB_APP_RESOURCE_ID and create private link
az network private-endpoint create -g $APP_PE_DEMO_RG -n webpe --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET \
    --private-connection-resource-id $WEB_APP_RESOURCE_ID --connection-name webpeconn -l $LOCATION

# Now access the site from the VM using the address https://[WebApp Name].azurewebsites.net
# Use the following URL to deploy the site using maven plugin: https://docs.microsoft.com/en-us/azure/app-service/containers/quickstart-java














#











# Setup the App using VSCode
# Go to the VM that you creaded ealier
# Use git to downlaod the code from https://github.com/naveedzaheer/simplespringwebapp.git
# Use VS Code to open the Folder
# 
# Open VSCode terminal
# Create three environment variables in the Terminal using the following commands
#   setx MYSQL_URL "jdbc:mysql://[server-name]].eastus.cloudapp.azure.com:3306/[db-name]"
#   setx MYSQL_USERNAME [MySQL User Name]
#   setx MYSQL_PASSWORD [My SQl password]
# Build the code using - mvn clean package
# Run the App using - mvn spring-boot:run -P production
# You should be able to access the app at - http://localhost:8080






