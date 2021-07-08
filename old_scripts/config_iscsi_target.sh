#!/bin/bash

#to run the script for iscsi target configuration
sudo zypper remove --non-interactive lio-utils python-rtslib python-configshell targetcli
sudo zypper install --non-interactive targetcli-fb dbus-1-python bash-com*
sudo systemctl enable targetcli
sudo systemctl start targetcli

# Create the root folder for all SBD devices
sudo mkdir /sbd

# Create the SBD device for the NFS server
sudo targetcli backstores/fileio create sbdnfs /sbd/sbdnfs 50M write_back=false
sudo targetcli iscsi/ create iqn.2006-04.nfs.local:nfs
sudo targetcli iscsi/iqn.2006-04.nfs.local:nfs/tpg1/luns/ create /backstores/fileio/sbdnfs
sudo targetcli iscsi/iqn.2006-04.nfs.local:nfs/tpg1/acls/ create iqn.2006-04.nfs-0.local:nfs-0
sudo targetcli iscsi/iqn.2006-04.nfs.local:nfs/tpg1/acls/ create iqn.2006-04.nfs-1.local:nfs-1

# save the targetcli changes
sudo targetcli saveconfig

# Output at the end
sudo targetcli ls
