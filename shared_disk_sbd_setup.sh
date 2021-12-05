#!/bin/bash

#configure the sbd device on the shared disk on lun2
LOGFILE='/var/log/azure/shared_disk_sbd_setup'
CONFIGFILE='/etc/sysconfig/sbd'
exec >> $LOGFILE
exec 2>&1

sudo systemctl enable sbd
# update the /etc/hosts
echo "10.0.0.5  nfs-0" >> /etc/hosts
echo "10.0.0.6  nfs-1" >> /etc/hosts

echo '-------'
echo 'Creating softdog config file'
echo softdog | sudo tee /etc/modules-load.d/softdog.conf
modprobe -v softdog
echo 'Confirm module is loaded:'
lsmod | grep softdog

hostname=`hostname`
if [ $hostname == 'nfs-0' ]
then
    echo "Formating the sbd disk and adding a label to it "
    sudo parted -s /dev/disk/azure/scsi1/lun2 mklabel GPT
    sudo parted -s /dev/disk/azure/scsi1/lun2 mkpart sbd-disk 1MiB 20MiB

    sudo partprobe
    sleep 5
    sudo ls -l /dev/disk/by-partlabel/sbd-disk 
fi

echo '======================='
date
echo 'Taking a copy of the config file'  
cp /etc/sysconfig/sbd /etc/sysconfig/sbd_backup

sbddevice='/dev/disk/by-partlabel/sbd-disk'
echo sbddevice=$sbddevice  

echo 'Check if the disk is already initialized'
sbd  -d $sbddevice dump
if [ $? -eq 0 ]
then
    echo 'sbd device is initialized , no need to run the command again'
else
    echo 'sbd device is not initialized, running the command now to do so'
    sbd -d $sbddevice -1 60 -4 120 create  
fi
echo '----'

sed -i 's,#SBD_DEVICE=\"\",SBD_DEVICE=\"'"$sbddevice"'\",' $CONFIGFILE
echo sbd device value is:   
grep 'SBD_DEVICE=' $CONFIGFILE  
echo '-------'
echo 'checking on the other 2 parameters in sbd config'  
source $CONFIGFILE

if [ $SBD_PACEMAKER == 'yes' ]
then 
    echo 'SBD_PACEMAKER value is set to yes'  
else
    echo 'Updateing the value for SBD_PACEMAKER to yes'  
    sed -i 's/^SBD_PACEMAKER.*$/SBD_PACEMAKER=yes/g' $CONFIGFILE
    echo 'New value is set to yes as in below:' 
    grep  'SBD_PACEMAKER=' $CONFIGFILE
fi

if [ $SBD_STARTMODE == 'always' ]
then
    echo 'SBD_STARTMODE is set to always'
else
    echo 'Updateing the value for SBD_STARTMODE to always'
    sed -i 's/^SBD_STARTMODE.*$/SBD_STARTMODE=always/g' $CONFIGFILE
    echo 'New value is set to yes as in below:'
    grep  'SBD_PACEMAKER=' $CONFIGFILE
fi

if [ $SBD_DELAY_START == 'yes' ]
then
    echo 'Needed delay is in place'
else
    echo 'Need to perform an update the value of SBD_DELAY_START to yes and add systemd delay .'
    sed -i 's/^SBD_DELAY_START.*$/SBD_DELAY_START=yes/g' $CONFIGFILE
    echo 'New value is set to yes as in below:'
    grep 'SBD_DELAY_START=' $CONFIGFILE
fi

echo 'Updating the systemd ..'
sudo mkdir /etc/systemd/system/sbd.service.d
echo -e "[Service]\nTimeoutSec=144" | sudo tee /etc/systemd/system/sbd.service.d/sbd_delay_start.conf
sudo systemctl daemon-reload

sbd  -d $sbddevice dump

echo 'Congrats we are done with preparing the sbd device, we shall move to the next steps'