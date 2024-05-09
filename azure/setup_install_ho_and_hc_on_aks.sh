#!/bin/bash
set -x

# Constants
PREFIX="user"
LOCATION="eastus"
RG="ho-mgmt"
MGMT_RG=${PREFIX}"-aks-rg"
AKS_CLUSTER_NAME=${PREFIX}"-aks-cluster"
MANAGED_RG_NAME="managed-aks-rg"
CUSTOMER_RG_NAME="customer-aks-rg"
CUSTOMER_NSG_RG_NAME="customer-nsg-rg"
CUSTOMER_VNET_NAME="customer-vnet"
CUSTOMER_VNET_SUBNET1="customer-subnet-1"
CUSTOMER_NSG="customer-nsg"
MGMT_DNS_ZONE_NAME="<yourDNSZone.com>"
EXTERNAL_DNS_NEW_SP_NAME="ExternalDnsServicePrincipal"
CUSTOM_HYPERSHIFT_IMAGE="<yourImageTag>"
CLUSTER_NAME=${PREFIX}"-hcp"
AZURE_CREDS="<yourAzureCredsFilepath>"
AZURE_BASE_DOMAIN=<yourBaseDomain.com>
PULL_SECRET=<yourPullSecretFilepath>
RELEASE_IMAGE=<yourReleaseImage>
HYPERSHIFT_BINARY_PATH="</blah/blah/.../hypershift/bin>"
SERVICE_PRINCIPAL_FILEPATH="</Users/<yourPath>/azure_mgmt.json>"

######################################## ExternalDNS Setup ########################################
# Create Azure RG and DNS Zone
az group create --name ${RG} --location ${LOCATION}
az network dns zone create --resource-group ${RG} --name ${MGMT_DNS_ZONE_NAME}

# Creating a service principal
DNS_SP=$(az ad sp create-for-rbac --name ${EXTERNAL_DNS_NEW_SP_NAME})
EXTERNAL_DNS_SP_APP_ID=$(echo "$DNS_SP" | jq -r '.appId')
EXTERNAL_DNS_SP_PASSWORD=$(echo "$DNS_SP" | jq -r '.password')

# Assign the rights for the service principal
DNS_ID=$(az network dns zone show --name ${MGMT_DNS_ZONE_NAME} --resource-group ${RG} --query "id" --output tsv)
az role assignment create --role "Reader" --assignee "${EXTERNAL_DNS_SP_APP_ID}" --scope "${DNS_ID}"
az role assignment create --role "Contributor" --assignee "${EXTERNAL_DNS_SP_APP_ID}" --scope "${DNS_ID}"

# Creating a configuration file for our service principal
cat <<-EOF > ${SERVICE_PRINCIPAL_FILEPATH}
{
  "tenantId": "$(az account show --query tenantId -o tsv)",
  "subscriptionId": "$(az account show --query id -o tsv)",
  "resourceGroup": "$RG",
  "aadClientId": "$EXTERNAL_DNS_SP_APP_ID",
  "aadClientSecret": "$EXTERNAL_DNS_SP_PASSWORD"
}
EOF

# Create needed secret with azure_mgmt.json
kubectl delete secret/azure-config-file --namespace "default"
kubectl create secret generic azure-config-file --namespace "default" --from-file ${SERVICE_PRINCIPAL_FILEPATH}

######################################## HyperShift Operator Install ########################################

# Apply some CRDs that are missing
oc apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
oc apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
oc apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
oc apply -f https://raw.githubusercontent.com/openshift/api/master/route/v1/zz_generated.crd-manifests/routes-Default.crd.yaml

# Install HO
${HYPERSHIFT_BINARY_PATH}/hypershift install \
--enable-conversion-webhook=false \
--external-dns-provider=azure \
--external-dns-credentials ${SERVICE_PRINCIPAL_FILEPATH} \
--pull-secret ${PULL_SECRET} \
--external-dns-domain-filter ${MGMT_DNS_ZONE_NAME} \
--managed-service ARO-HCP \
--hypershift-image ${CUSTOM_HYPERSHIFT_IMAGE}

######################################## Create Hosted Cluster ########################################

# Delete any previous instances of the resource groups
az group delete -n ${MANAGED_RG_NAME} --yes
az group delete -n ${CUSTOMER_RG_NAME} --yes
az group delete -n ${CUSTOMER_NSG_RG_NAME} --yes

# Create managed resource group
az group create --name ${MANAGED_RG_NAME} --location ${LOCATION}

# Create customer resource group
az group create --name ${CUSTOMER_RG_NAME} --location ${LOCATION}

# Create customer nsg resource group
az group create --name ${CUSTOMER_NSG_RG_NAME} --location ${LOCATION}

# Create customer network security group
az network nsg create --resource-group ${CUSTOMER_NSG_RG_NAME} --name ${CUSTOMER_NSG}

# Get customer nsg ID
GetNsgID=$(az network nsg list --query "[?name=='${CUSTOMER_NSG}'].id" -o tsv)

# Create customer vnet in customer resource group
az network vnet create \
    --name ${CUSTOMER_VNET_NAME} \
    --resource-group ${CUSTOMER_RG_NAME} \
    --address-prefix 10.0.0.0/16 \
    --subnet-name ${CUSTOMER_VNET_SUBNET1} \
    --subnet-prefixes 10.0.0.0/24 \
    --nsg ${GetNsgID}

# Get customer vnet ID
GetVnetID=$(az network vnet list --query "[?name=='${CUSTOMER_VNET_NAME}'].id" -o tsv)

${HYPERSHIFT_BINARY_PATH}/hypershift create cluster azure \
--name $CLUSTER_NAME \
--azure-creds $AZURE_CREDS \
--location ${LOCATION} \
--node-pool-replicas 2 \
--base-domain $AZURE_BASE_DOMAIN \
--pull-secret $PULL_SECRET \
--generate-ssh \
--release-image ${RELEASE_IMAGE} \
--external-dns-domain ${MGMT_DNS_ZONE_NAME} \
--resource-group-name ${MANAGED_RG_NAME} \
--vnet-id "${GetVnetID}" \
--annotations hypershift.openshift.io/pod-security-admission-label-override=baseline \
--control-plane-operator-image=${CUSTOM_HYPERSHIFT_IMAGE} \
--annotations hypershift.openshift.io/certified-operators-catalog-image=registry.redhat.io/redhat/certified-operator-index@sha256:fc68a3445d274af8d3e7d27667ad3c1e085c228b46b7537beaad3d470257be3e \
--annotations hypershift.openshift.io/community-operators-catalog-image=registry.redhat.io/redhat/community-operator-index@sha256:4a2e1962688618b5d442342f3c7a65a18a2cb014c9e66bb3484c687cfb941b90 \
--annotations hypershift.openshift.io/redhat-marketplace-catalog-image=registry.redhat.io/redhat/redhat-marketplace-index@sha256:ed22b093d930cfbc52419d679114f86bd588263f8c4b3e6dfad86f7b8baf9844 \
--annotations hypershift.openshift.io/redhat-operators-catalog-image=registry.redhat.io/redhat/redhat-operator-index@sha256:59b14156a8af87c0c969037713fc49be7294401b10668583839ff2e9b49c18d6 \
--fips=true

set +x