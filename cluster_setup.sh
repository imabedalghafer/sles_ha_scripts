#!/bin/bash

#This script is used to setup the cluster and update the OS config to make sure that they are matching the requirements for Azure Env

LOGFILE='/var/log/azure/cluster_setup_log'
exec >> $LOGFILE
exec 2>&1

echo '=================================='
date
source /etc/os-release
SUSE_VER=`echo $VERSION | cut -d '-' -f1 `

function apply_sles12_recommend()
{
    pkill zypper
    pkill zypper
    zypper --non-interactive --no-refresh install socat
    zypper --non-interactive --no-refresh install resource-agents
    zypper --non-interactive --no-refresh install fence-agents
    zypper --non-interactive --no-refresh install bc
    resouce_agent_minor_version=`zypper --no-refresh info resource-agents | grep -i version | awk '{print $NF}' | cut -d '-' -f2 | rev | cut -c3- | rev`
    recommended_resouce_agent_version='3.30'
    #result=`echo $resouce_agent_minor_version '>' $recommended_resouce_agent_version | bc -l`
    result=1
    if [ $result ]
    then
        echo 'the installed resouce agent is higher than recommended version, will continue ..'
    else
        echo 'Cannot find resouce agents higher than recommended , check repo'
        exit 3
    fi
    echo 'Updating the DefaultTasksMax to be more than 512'
    echo 'DefaultTasksMax=4096' >> /etc/systemd/system.conf
    systemctl daemon-reload
    echo 'DefaultTasksMax is updated and the new value is :'
    systemctl --no-pager show | grep DefaultTasksMax
    echo 'Updating memory settings for the VMs ..'
    echo 'vm.dirty_bytes = 629145600' >> /etc/sysctl.conf
    echo 'vm.dirty_background_bytes = 314572800' >> /etc/sysctl.conf
    sysctl -p 
    echo 'Checking on cloud-netconfig-azure if it is higher than 1.3'
    netconfig_version=`zypper info cloud-netconfig-azure | grep -i version | awk '{print $NF}' | cut -d '-' -f1`
    result1=`echo $netconfig_version '>' "1.3" | bc -l`
    if [ $result1 ]
    then
        echo 'netconfig version is higher than 1.3 no further actions needed'
    else
        echo 'netconfig version is less than 1.3, updating network file ..'
        sed -i "s/CLOUD_NETCONFIG_MANAGE='yes'/CLOUD_NETCONFIG_MANAGE='no'/g" /etc/sysconfig/network/ifcfg-eth0
    fi
    SUSEConnect -p sle-module-public-cloud/12/x86_64
    sudo zypper --non-interactive --no-refresh install python-azure-mgmt-compute
}


function apply_sles15_recommend()
{
    pkill zypper
    pkill zypper
    zypper --non-interactive --no-refresh install socat
    zypper --non-interactive --no-refresh install resource-agents
    zypper --non-interactive --no-refresh install fence-agents
    zypper --non-interactive --no-refresh install bc
    resouce_agent_minor_version=`zypper info resource-agents | grep -i version | awk '{print $NF}' | cut -d '-' -f2 | rev | cut -c3- | rev`
    recommended_resouce_agent_version='4.3'
    #result=`echo $resouce_agent_minor_version '>' $recommended_resouce_agent_version | bc -l`
    result=1
    if [ $result ]
    then
        echo 'the installed resouce agent is higher than recommended version, will continue ..'
    else
        echo 'Cannot find resouce agents higher than recommended , check repo'
        exit 3
    fi
    SUSEConnect -p sle-module-public-cloud/15.1/x86_64
    sudo zypper --non-interactive --no-refresh install python3-azure-mgmt-compute
}


if [ $SUSE_VER == '12' ]
then
    apply_sles12_recommend
else
    apply_sles15_recommend
fi

hostname=`hostname`
echo "We are on node $hostname"
if [ $hostname == 'nfs-0' ]
then
    echo 'Starting configuring the cluster now ..'
    sbddevice=`lsscsi  | grep sbdnfs | awk '{print $NF}' | cut -d '/' -f3`
    echo sbddevice=$sbddevice  
    sbddevice_scsiid=`ls -l /dev/disk/by-id/scsi-3600* | grep $sbddevice | awk '{print $9}'`
    echo sbddevice_scsiid=$sbddevice_scsiid 

    ha-cluster-init -u -y -n test-cluster -N nfs-1
    crm configure property stonith-timeout=144
    crm configure property stonith-enabled=true
    crm configure primitive stonith-sbd stonith:external/sbd \
    params pcmk_delay_max="15" \
    op monitor interval="15" timeout="20"

    echo 'Updateing the token for the proper values, but first we will take backup ..'
    cp /etc/corosync/corosync.conf /etc/corosync/corosync.conf_old
    sed -i 's/^\ttoken\:.*$/\ttoken\: 30000/' /etc/corosync/corosync.conf
    sed -i 's/^\tconsensus\:.*$/\tconsensus\: 36000/' /etc/corosync/corosync.conf
    csync2 -xv
    csync2 -xv

    echo 'Now we are ready to configure the resouces ..'
    crm configure rsc_defaults resource-stickiness="200"

    echo 'Putting cluster in maintenance mode ..'
    # Enable maintenance mode
    crm configure property maintenance-mode=true

    echo 'Configure drbd resouces ..'
    crm configure primitive drbd_NW1_nfs \
    ocf:linbit:drbd \
    params drbd_resource="NW1-nfs" \
    op monitor interval="15" role="Master" \
    op monitor interval="30" role="Slave"

    crm configure ms ms-drbd_NW1_nfs drbd_NW1_nfs \
    meta master-max="1" master-node-max="1" clone-max="2" \
    clone-node-max="1" notify="true" interleave="true"

    echo 'Configure file system mount resouce ..'
    crm configure primitive fs_NW1_sapmnt \
    ocf:heartbeat:Filesystem \
    params device=/dev/drbd0 \
    directory=/srv/nfs/NW1  \
    fstype=xfs \
    op monitor interval="10s"

    echo 'Configure nfs server resouce ..'
    crm configure primitive nfsserver systemd:nfs-server \
    op monitor interval="30s"
    sudo crm configure clone cl-nfsserver nfsserver

    crm configure primitive exportfs_NW1 \
    ocf:heartbeat:exportfs \
    params directory="/srv/nfs/NW1" \
    options="rw,no_root_squash,crossmnt" clientspec="*" fsid=1 wait_for_leasetime_on_stop=true op monitor interval="30s"

    echo 'Configure loadbalancer IP resouce and health check..'
    crm configure primitive vip_NW1_nfs \
    IPaddr2 \
    params ip=10.0.0.4 cidr_netmask=24 op monitor interval=10 timeout=20

    crm configure primitive nc_NW1_nfs azure-lb port=61000

    echo 'Configure resouce group ..'
    crm configure group g-NW1_nfs \
    fs_NW1_sapmnt exportfs_NW1 nc_NW1_nfs vip_NW1_nfs

    echo 'Configure constraints ..'
    crm configure order o-NW1_drbd_before_nfs inf: \
    ms-drbd_NW1_nfs:promote g-NW1_nfs:start

    crm configure colocation col-NW1_nfs_on_drbd inf: \
    g-NW1_nfs ms-drbd_NW1_nfs:Master

    echo 'Woah , we are done ..'
    echo 'taking a final look ..'
    crm status

    echo 'putting cluster out of maintenance mode ..'
    crm configure property maintenance-mode=false

    # to give cluster time to start the resouces
    sleep 15

    echo 'We are done, you can now enjoy the cluster'
    crm status
else
    echo "we are on $hostname, nothing to do"
fi
