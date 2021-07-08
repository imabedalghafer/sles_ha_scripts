#!/bin/bash
# build the rg , AS and 2 VMs for NFS share and one VM for iscsi target

rgname="sles-ha-rg"
loc="eastus"
asname="slesha"
vmname1="nfs-0"
vmname2="nfs-1"
vmname3="sbd-storage"
lbname="sles-ha-lb"
vnetname="havnet"
subnetname="hasubnet"
sku_size="Standard_D2s_v3"
offer="SUSE:sles-sap-15-sp1:gen1:2020.06.10"
frontendip="nw01"
backendpoolname="nfs-cls"
probename="nw1-probe"

if [ -f "./username.txt" ] 
then 
    username=`cat username.txt`
else
    read -p "Please enter the username: " username
fi

if [ -f "./password.txt" ]
then
    password=`cat password.txt`
else
    read -s -p "Please enter the password: " password
fi

az group create --name $rgname --location $loc
az network vnet create --name $vnetname -g $rgname --address-prefixes 10.0.0.0/24 --subnet-name $subnetname --subnet-prefixes 10.0.0.0/24
az vm availability-set create -n $asname -g $rgname --platform-fault-domain-count 3 --platform-update-domain-count 20

az network lb create --resource-group $rgname --name $lbname --location $loc --backend-pool-name $backendpoolname --frontend-ip-name $frontendip --private-ip-address "10.0.0.4" --sku "Standard" --vnet-name $vnetname --subnet $subnetname


az vm create -g $rgname -n $vmname1 --admin-username $username --admin-password $password  --availability-set $asname --image $offer --data-disk-sizes-gb 30 --vnet-name $vnetname --subnet $subnetname --public-ip-sku Standard
az vm create -g $rgname -n $vmname2 --admin-username $username --admin-password $password  --availability-set $asname --image $offer --data-disk-sizes-gb 30 --vnet-name $vnetname --subnet $subnetname --public-ip-sku Standard
az vm create -g $rgname -n $vmname3 --admin-username $username --admin-password $password  --image $offer --vnet-name $vnetname --subnet $subnetname

az network lb probe create --lb-name $lbname --resource-group $rgname --name $probename --port 61000 --protocol Tcp

nic1name1=`az vm show -g $rgname -n $vmname1  --query networkProfile.networkInterfaces[].id -o tsv | cut -d / -f 9`
az network nic ip-config address-pool add --address-pool $backendpoolname --ip-config-name ipconfig$vmname1 --nic-name $nic1name1 --resource-group $rgname --lb-name $lbname

nic1name2=`az vm show -g $rgname -n $vmname2  --query networkProfile.networkInterfaces[].id -o tsv | cut -d / -f 9`
az network nic ip-config address-pool add --address-pool $backendpoolname --ip-config-name ipconfig$vmname2 --nic-name $nic1name2 --resource-group $rgname --lb-name $lbname

az network lb rule create --resource-group $rgname --lb-name $lbname --name "nw1-rule" --backend-port 0 --frontend-port 0 \
 --frontend-ip-name $frontendip --backend-pool-name $backendpoolname --protocol All --floating-ip true \
 --idle-timeout 30 --probe-name $probename

 az vm run-command invoke -g $rgname -n $vmname3 --command-id RunShellScript --scripts @config_iscsi_target.sh

 az vm run-command invoke -g $rgname -n $vmname1 --command-id RunShellScript --scripts @config_iscsi_initiator.sh &
 az vm run-command invoke -g $rgname -n $vmname2 --command-id RunShellScript --scripts @config_iscsi_initiator.sh 
