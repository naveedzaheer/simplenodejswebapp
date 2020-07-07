# Please provide your subscription id here
export APP_SUBSCRIPTION_ID=03228871-7f68-4594-b208-2d8207a65428
# Please provide your unique prefix to make sure that your resources are unique
export APP_PREFIX=nzscus01
# Please provide your region
export LOCATION=SouthCentralUS
# Please provide your OS
export IS_LINUX=true
export IS_CONTAINER=true
export OS_TYPE=Linux #Windows

export VNET_PREFIX="10.20."

export APP_PE_DEMO_RG=$APP_PREFIX"-webappdemo-rg"
export DEMO_VNET=$APP_PREFIX"-webappdemo-vnet"
export DEMO_VNET_CIDR=$VNET_PREFIX"0.0/16"
export DEMO_VNET_APP_SUBNET=app_subnet
export DEMO_VNET_APP_SUBNET_CIDR=$VNET_PREFIX"1.0/24"
export DEMO_VNET_PL_SUBNET=pl_subnet
export DEMO_VNET_PL_SUBNET_CIDR=$VNET_PREFIX"2.0/24"

export DEMO_APP_PLAN=$APP_PREFIX"-webapp-plan"
export DEMO_APP_NAME=$APP_PREFIX"-web-app"

export DEMO_APP_VM=pldemovm
export DEMO_APP_VM_ADMIN=azureuser
export DEMO_VM_IMAGE=MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest
export DEMO_VM_SIZE=Standard_DS2_v2
export DEMO_APP_KV=$APP_PREFIX"-kv1"
export DEMO_APP_ACR=$APP_PREFIX"acr"

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
# - NodeJS
# - VS Code
# - Azure CLI
az vm create -n $DEMO_APP_VM -g $APP_PE_DEMO_RG --image MicrosoftWindowsServer:WindowsServer:2019-Datacenter:latest \
   --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET --public-ip-sku Standard --size $DEMO_VM_SIZE --admin-username $DEMO_APP_VM_ADMIN

# Capture public IP of the jump/DNS box
# 52.188.33.128

# Install VS Code - https://code.visualstudio.com/download
# Setup DNS server
# Windows DNS Server - https://www.wintelpro.com/install-and-configure-dns-on-windows-server-2019/

if [ $IS_CONTAINER = true ]; then
    # Create ACR and note down the user name and password for the repo as it will be used on line 70/71
    az acr create -n $DEMO_APP_ACR -g $APP_PE_DEMO_RG -l $LOCATION --admin-enabled true --sku Standard

    # After the build is complete find the image name it should imilar to nz007lindockacr.azurecr.io/simplenodewebapp:ch2
    az acr build -t $DEMO_APP_NAME":{{.Run.ID}}" -r $DEMO_APP_ACR .

    ACR_IMAGE_TAG=$(az acr repository show-tags --name $DEMO_APP_ACR --repository $DEMO_APP_NAME --query [0] -o tsv)
    export CONTAINER_IMAGE_NAME=$DEMO_APP_ACR".azurecr.io/"$DEMO_APP_NAME":"$ACR_IMAGE_TAG
fi

# Create App Service Plan
if [ $IS_LINUX == true ]; then
    az appservice plan create -g $APP_PE_DEMO_RG -l $LOCATION -n $DEMO_APP_PLAN --is-linux --number-of-workers 1 --sku P1V2
else
    if [ $IS_CONTAINER == true ]; then
        az appservice plan create -g $APP_PE_DEMO_RG -l $LOCATION -n $DEMO_APP_PLAN --hyper-v --number-of-workers 1 --sku P1V2
    else
        az appservice plan create -g $APP_PE_DEMO_RG -l $LOCATION -n $DEMO_APP_PLAN --number-of-workers 1 --sku P1V2
    fi
fi

# Create Node JS Web App
if [ $IS_CONTAINER == true ]; then
    ACR_UID=$(az acr credential show -n $DEMO_APP_ACR --query username -o tsv)
    ACR_PWD=$(az acr credential show -n $DEMO_APP_ACR --query passwords[0].value -o tsv)
    az webapp create -g $APP_PE_DEMO_RG -p $DEMO_APP_PLAN -n $DEMO_APP_NAME -i $CONTAINER_IMAGE_NAME \
        -s $ACR_UID -w $ACR_PWD
else
    az webapp create -g $APP_PE_DEMO_RG -p $DEMO_APP_PLAN -n $DEMO_APP_NAME --runtime "NODE|10-lts"
fi


# Create and Capture identity from output
az webapp identity assign -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME
APP_MSI=$(az webapp show --name $DEMO_APP_NAME -g $APP_PE_DEMO_RG --query identity.principalId -o tsv)

# Create Key Vault
az keyvault create --location $LOCATION --name $DEMO_APP_KV --resource-group $APP_PE_DEMO_RG --enable-soft-delete true

# Set Key Vault Secrets
# Please  take a note of the Secret Full Path and save it as KV_SECRET_DB_UID_FULLPATH
az keyvault secret set --vault-name $DEMO_APP_KV --name "$KV_SECRET_APP_MESSAGE" --value "$KV_SECRET_APP_MESSAGE_VALUE"

# Capture the KV URI
# az keyvault show --name $DEMO_APP_KV --resource-group $APP_PE_DEMO_RG
export KV_URI="/subscriptions/"$APP_SUBSCRIPTION_ID"/resourceGroups/"$APP_PE_DEMO_RG"/providers/Microsoft.KeyVault/vaults/"$DEMO_APP_KV

# Set Policy for Web App to access secrets
az keyvault set-policy -g  $APP_PE_DEMO_RG --name $DEMO_APP_KV --object-id $APP_MSI --secret-permissions get list --verbose

az webapp config appsettings set -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --settings $KV_SECRET_APP_MESSAGE_VAR="$KV_SECRET_APP_MESSAGE"

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
PRIVATE_KV_IP=$(az network private-endpoint create -g $APP_PE_DEMO_RG -n kvpe --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET \
    --private-connection-resource-id "$KV_URI" --connection-name kvpeconn -l $LOCATION --group-id "vault" --query customDnsConfigs[0].ipAddresses[0] -o tsv)

# Creating Forward Lookup Zones in the DNS server you created above
# You may be using root hints for DNS resolution on your custom DNS server.
# Please add 168.63.129.16 as default forwarder on you custom DNS server.
# https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverforwarder?view=win10-ps

#   Create the zone for: vault.azure.net
#       Create an A Record for the Key Vault with the name and its private endpoint address

# Switch to custom DNS on VNET
# export DEMO_APP_VM_IP="10.0.2.4"
# az network vnet update -g $APP_PE_DEMO_RG -n $DEMO_VNET --dns-servers $DEMO_APP_VM_IP

# Private DNS Zones
export AZUREKEYVAULT_ZONE=privatelink.vaultcore.azure.net
az network private-dns zone create -g $APP_PE_DEMO_RG -n $AZUREKEYVAULT_ZONE
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREKEYVAULT_ZONE -n $DEMO_APP_KV -a $PRIVATE_KV_IP
az network private-dns link vnet create -g $APP_PE_DEMO_RG --virtual-network $DEMO_VNET --zone-name $AZUREKEYVAULT_ZONE --name kvdnsLink --registration-enabled false

#
# Change KV firewall - allow only PE access

# Verify it's locked down (click on Secrets from browser)
#

# Attach Web App to the VNET (VNET integration)
az webapp vnet-integration add -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME --vnet $DEMO_VNET --subnet $DEMO_VNET_APP_SUBNET

######################################################################################################
# Use VSCode to deploy the web app
######################################################################################################
##################################################################################################
# !!!!!!!!!!!!!!!!!!!!!!!!Stop Here Before Creating the Private Endpoint for Wev app!!!!!!!!!!!!!
# You should now use VSCode to push the nodejs Web App to the App Service
# Test the App to make sure that it is running
##################################################################################################

# Now restart the webapp
az webapp restart -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME
# ...and verify it still has access to KV

# Get the webapp resource id
az webapp show -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME

export WEB_APP_RESOURCE_ID="/subscriptions/"$APP_SUBSCRIPTION_ID"/resourceGroups/"$APP_PE_DEMO_RG"/providers/Microsoft.Web/sites/"$DEMO_APP_NAME


# Create Web App Private Link
PRIVATE_APP_IP=$(az network private-endpoint create -g $APP_PE_DEMO_RG -n webapppe --vnet-name $DEMO_VNET --subnet $DEMO_VNET_PL_SUBNET \
    --private-connection-resource-id $WEB_APP_RESOURCE_ID --connection-name webapppeconn -l $LOCATION --group-id "sites" --query customDnsConfigs[0].ipAddresses[0] -o tsv)

export AZUREWEBSITES_ZONE=privatelink.azurewebsites.net
az network private-dns zone create -g $APP_PE_DEMO_RG -n $AZUREWEBSITES_ZONE
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREWEBSITES_ZONE -n $DEMO_APP_NAME -a $PRIVATE_APP_IP
az network private-dns record-set a add-record -g $APP_PE_DEMO_RG -z $AZUREWEBSITES_ZONE -n $DEMO_APP_NAME".scm" -a $PRIVATE_APP_IP

# Link zones to VNET
az network private-dns link vnet create -g $APP_PE_DEMO_RG -n webapppe-link -z $AZUREWEBSITES_ZONE -v $DEMO_VNET -e False

az webapp log tail -g $APP_PE_DEMO_RG -n $DEMO_APP_NAME




