#!/bin/bash

#configure the data device on the shared disk on lun3
LOGFILE='/var/log/azure/shared_disk_data_setup'
exec >> $LOGFILE
exec 2>&1

hostname=`hostname`
if [ $hostname == 'nfs-0' ]
then
    echo "Creating a volume group on the shared data disk"
    sudo parted -s /dev/disk/azure/scsi1/lun3 mklabel GPT
    sudo parted -s /dev/disk/azure/scsi1/lun3 mkpart data-shared 1GiB 29GiB

    echo "Verifing the data .."
    sudo partprobe
    sleep 10
    sudo ls -l /dev/disk/by-partlabel/

    echo "Creating the volume group"
    sudo pvcreate /dev/disk/by-partlabel/data-shared
    sudo vgcreate vg-NW1-NFS /dev/disk/by-partlabel/data-shared
    sudo lvcreate -l 100%FREE -n NW1 vg-NW1-NFS
    sleep 10
    sudo mkfs.xfs /dev/vg-NW1-NFS/NW1


    echo 'Verifing the mount state'
    mkdir -p /srv/nfs/NW1
    mount -t xfs /dev/vg-NW1-NFS/NW1 /srv/nfs/NW1
    if [ $? -eq 0 ]
    then
        df -h /srv/nfs/NW1
        umount /srv/nfs/NW1
    else
        echo 'There is an issue , please check ..'
    fi

fi

echo "Updating the LVM config "
cp /etc/lvm/lvm.conf /etc/lvm/lvm.conf_backup_script

sudo lvmconfig global/system_id_source
sed -i 's/system_id_source.*$/system_id_source = \"uname\"/g' /etc/lvm/lvm.conf
sudo lvmconfig global/system_id_source

#sudo lvmconfig activation/auto_activation_volume_list
#sed -i '/^activation.*/a auto_activation_volume_list = []' /etc/lvm/lvm.conf
#sudo lvmconfig activation/auto_activation_volume_list                 

echo "Updating the nfs server configuration .. "
cp /etc/sysconfig/nfs /etc/sysconfig/nfs_backup_script
sed -i 's/^NFSV4LEASETIME.*$/NFSV4LEASETIME="60"/g' /etc/sysconfig/nfs
grep NFSV4LEASETIME  /etc/sysconfig/nfs


echo "Starting with final phase cluster setup .."