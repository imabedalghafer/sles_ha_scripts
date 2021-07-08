#!/bin/bash

# Config the iscsi initiator and connect to target
# Config the local disks and create the LVM

sudo systemctl enable iscsid
sudo systemctl enable iscsi
sudo systemctl enable sbd

cp /etc/iscsi/initiatorname.iscsi /etc/iscsi/initiatorname.iscsi.orig
 
hostname=`hostname`
if [ $hostname == "nfs-0" ]
then
    echo "InitiatorName=iqn.2006-04.nfs-0.local:nfs-0" > /etc/iscsi/initiatorname.iscsi
else
    echo "InitiatorName=iqn.2006-04.nfs-0.local:nfs-1" > /etc/iscsi/initiatorname.iscsi
fi

sudo systemctl restart iscsid
sudo systemctl restart iscsi

sudo iscsiadm -m discovery --type=st --portal=10.0.0.7:3260   
sudo iscsiadm -m node -T iqn.2006-04.nfs.local:nfs --login --portal=10.0.0.7:3260
sudo iscsiadm -m node -p 10.0.0.7:3260 -T iqn.2006-04.nfs.local:nfs --op=update --name=node.startup --value=automatic

# add the softdog module as needed from sbd
echo softdog | sudo tee /etc/modules-load.d/softdog.conf
sudo modprobe -v softdog


# update the /etc/hosts
echo "10.0.0.5  nfs-0" >> /etc/hosts
echo "10.0.0.6  nfs-1" >> /etc/hosts

sudo zypper install --non-interactive drbd drbd-kmp-default drbd-utils

sudo sh -c 'echo -e "n\n\n\n\n\nw\n" | fdisk /dev/disk/azure/scsi1/lun0'
sudo pvcreate /dev/disk/azure/scsi1/lun0-part1  
sudo vgcreate vg-NW1-NFS /dev/disk/azure/scsi1/lun0-part1
sudo lvcreate -l 100%FREE -n NW1 vg-NW1-NFS


### tasks left
cat << EOF > /root/tasks_remaining
1. start with configuring the SBD device
2. setup the drbd disks 
3. setup the cluster
EOF
