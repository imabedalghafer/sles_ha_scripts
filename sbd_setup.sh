#!/bin/bash
### This script is used to setup the sbd devices on the test cluster lab


LOGFILE='/var/log/azure/sbd_setup_log'
CONFIGFILE='/etc/sysconfig/sbd'
exec >> $LOGFILE
exec 2>&1

echo '======================='
date
echo 'Taking a copy of the config file'  
cp /etc/sysconfig/sbd /etc/sysconfig/sbd_backup

sbddevice=`lsscsi  | grep sbdnfs | awk '{print $NF}' | cut -d '/' -f3`
echo sbddevice=$sbddevice  
sbddevice_scsiid=`ls -l /dev/disk/by-id/scsi-3600* | grep $sbddevice | awk '{print $9}'`
echo sbddevice_scsiid=$sbddevice_scsiid  

echo 'Check if the disk is already initialized'
sbd  -d $sbddevice_scsiid dump
if [ $? -eq 0 ]
then
    echo 'sbd device is initialized , no need to run the command again'
else
    echo 'sbd device is not initialized, running the command now to do so'
    sbd -d $sbddevice_scsiid -1 60 -4 120 create  
fi
echo '----'

#replace the sbd device with the scsi id of the device
sed -i 's,#SBD_DEVICE=\"\",SBD_DEVICE=\"'"$sbddevice_scsiid"'\",' $CONFIGFILE
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
echo '-------'
echo 'Creating softdog config file'
echo softdog | sudo tee /etc/modules-load.d/softdog.conf
modprobe -v softdog
echo 'Confirm module is loaded:'
lsmod | grep softdog

echo 'Congrats we are done with preparing the sbd device, we shall move to the next steps'
