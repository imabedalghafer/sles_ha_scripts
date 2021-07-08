#!/bin/bash
#Used to configure the drbd devices that will be used by the nfs cluster

LOGFILE='/var/log/azure/drbd_setup_log'
exec >> $LOGFILE
exec 2>&1

echo '======================================='
date
echo 'installing required packages'
zypper --non-interactive install  drbd drbd-kmp-default drbd-utils

echo 'Adding the recommended settings for drbd as per the documentation'
echo 'But first we will take a backup of the original file'
cp /etc/drbd.d/global_common.conf /etc/drbd.d/global_common.conf_backup
cat << EOF > /etc/drbd.d/global_common.conf
global {
     usage-count no;
}
common {
     handlers {
          fence-peer "/usr/lib/drbd/crm-fence-peer.sh";
          after-resync-target "/usr/lib/drbd/crm-unfence-peer.sh";
          split-brain "/usr/lib/drbd/notify-split-brain.sh root";
          pri-lost-after-sb "/usr/lib/drbd/notify-pri-lost-after-sb.sh; /usr/lib/drbd/notify-emergency-reboot.sh; echo b > /proc/sysrq-trigger ; reboot -f";
     }
     startup {
          wfc-timeout 0;
     }
     options {
     }
     disk {
          md-flushes yes;
          disk-flushes yes;
          c-plan-ahead 1;
          c-min-rate 100M;
          c-fill-target 20M;
          c-max-rate 4G;
     }
     net {
          after-sb-0pri discard-younger-primary;
          after-sb-1pri discard-secondary;
          after-sb-2pri call-pri-lost-after-sb;
          protocol     C;
          tcp-cork yes;
          max-buffers 20000;
          max-epoch-size 20000;
          sndbuf-size 0;
          rcvbuf-size 0;
     }
}
EOF

echo 'Creating the drbd devices config file'
cat << EOF > /etc/drbd.d/NW1-nfs.res
resource NW1-nfs {
     protocol     C;
     disk {
          on-io-error       detach;
     }
     on nfs-0 {
          address   10.0.0.5:7790;
          device    /dev/drbd0;
          disk      /dev/vg-NW1-NFS/NW1;
          meta-disk internal;
     }
     on nfs-1 {
          address   10.0.0.6:7790;
          device    /dev/drbd0;
          disk      /dev/vg-NW1-NFS/NW1;
          meta-disk internal;
     }
}
EOF

echo 'Creating the drbd devices and starting them'
drbdadm create-md NW1-nfs
drbdadm up NW1-nfs

echo 'Create nfs mount point'
mkdir -p /srv/nfs/NW1

hostname=`hostname`
if [ $hostname == 'nfs-0' ]
then
    echo 'Starting the initialization of drbd device'
    sudo drbdadm new-current-uuid --clear-bitmap NW1-nfs
    sudo drbdadm primary --force NW1-nfs
    sudo drbdsetup wait-sync-resource NW1-nfs
    echo 'initialization done, below is the status'
    sudo drbdadm status
    mkfs.xfs /dev/drbd0
    mount -t xfs /dev/drbd0 /srv/nfs/NW1
    echo 'Drbd disk is formated and mounted'
    df -h /srv/nfs/NW1
    echo 'umounting disk now'
    umount /dev/drbd0 
fi

echo 'Congrats , we are done with the drbd setup you can now start setting up the cluster'