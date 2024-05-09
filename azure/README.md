# General
Before running either of these scripts, run `az login` and login to your Azure account.

## setup_aks_cluster.sh
This script will:
* Clean out any existing AKS cluster you may have spun up using the script.
* Create a resource group for the AKS cluster
* Create a FIPS enabled AKS cluster
* Get the kubeconfig for the AKS cluster


## setup_install_ho_and_hc_on_aks.sh
Be mindful, you will need to set up all the constants. This script sets up things as it would be expected in a real world ARO HCP SD & customer use case

This script will:
* Create a resource group for the Azure DNS zone needed for externalDNS
* Create a service principal for the Azure DNS zone and assign rights to it
* Create a configuration file from the service principal configuration
* Create the needed secret for externalDNS
* Apply prometheus and OpenShift CRDs needed for creating Hosted Clusters
* Install the HyperShift Operator
* Clean out any existing resource groups created for the hosted cluster, created by this script
* Create a resource group which represents the managed services resource group, aka MANAGED_RG_NAME
* Create a resource group which represents the customer resource group, which in a real world use case would contain an existing VNET and subnet (and possibly a network security group), aka CUSTOMER_RG_NAME
* Create a resource group which represents the customer resource group containing only a network security group, aka CUSTOMER_NSG_RG_NAME
* Create a network security group in CUSTOMER_NSG_RG_NAME
* Create a VNET and subnet in CUSTOMER_RG_NAME
* Create an Azure, FIPS enabled Hosted Cluster