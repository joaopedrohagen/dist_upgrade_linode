#!/bin/bash

###################################################################
#-----------------------------------------------------------------#
# Script Name: dist_upgrade_linode.sh                             #
#-----------------------------------------------------------------#
# Description: This Script makes the distro upgrade safely.       #
# It integrates Linode's API by taking a Snapshot before starting # 
# the upgrade and, if it doesn't work, it returns to the previous # 
# configuration through the Snapshot.                             #
#-----------------------------------------------------------------#
# Site: https://hagen.dev.br                                      #
#-----------------------------------------------------------------#
# Author: João Pedro Hagen <joaopedro@hagen.dev.br>               #
# ----------------------------------------------------------------#
# History:                                                        #
#   V1.0.1 2023-05-14                                             #
#       -Initial release. Installing,                             #
#-----------------------------------------------------------------#

# Installation of jq to handle json data
echo -e "\e[1;35mInstalling jq for json handling...\e[0m";
sleep 3;
apt install jq -y > /dev/null 2>&1;

API_KEY='<YOUR_API_KEY_HERE>'
LINODE_ID=$(cat /sys/devices/virtual/dmi/id/product_serial)

# Take a new Snapshot
echo -e "\e[1;35mTaking the Snapshot. Wait until the next step. This usually takes time.\e[0m";
echo;
sleep 5;
curl -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -X POST -d '{
        "label": "Backup_Distro_Upgrade"
    }' \
    https://api.linode.com/v4/linode/instances/"$LINODE_ID"/backups > /root/.snaplog.json 2> /dev/null;

# Check Snapshot status
while [ "$SNAP_STATUS" != '"successful"' ] 
do

    SNAP_ID=$(jq '.id' /root/.snaplog.json)
    SNAP_STATUS=$(jq '.status' /root/.snapstatus.json 2>/dev/null)

    curl -H "Authorization: Bearer $API_KEY" \
        https://api.linode.com/v4/linode/instances/"$LINODE_ID"/backups/"$SNAP_ID" > /root/.snapstatus.json 2> /dev/null;

done

echo -e "\e[1;35mSnapshot completed successfully!\e[0m";
sleep 3;
echo -e "\e[1;35mStarting distro upgrade. This may take some time. Wait until the terminal becomes available again.\e[0m";

UPDATE_MANAGER_VERIFY=$(cat /etc/update-manager/release-upgrades | grep 'Prompt' | cut -d '=' -f 2)

# Checks if the release-upgrades file is set with prompt value=lts.
if [ "$UPDATE_MANAGER_VERIFY" != 'lts' ]; then
    sed -i 's/^Prompt=.*/Prompt=lts/' /etc/update-manager/release-upgrades;
fi

echo "Installing update-manager-core";
apt install update-manager-core -y > /dev/null 2>&1;
sleep 2;
echo "Updating repositories";
apt update > /dev/null 2>&1;
sleep 2;
echo "Updating packages";
sleep 2;
echo;
apt upgrade -y;
apt dist-upgrade -y;

echo "Starting do-release-upgrade";
sleep 3;
echo -e "\e[1;31mWARNING!\e[0m Choose next options carefully."
sleep 3;
yes | do-release-upgrade -m server -f DistUpgradeViewNonInteractive -q;

if [ $? -eq 0 ]; then
    echo -e "\e[1;32mUpdate completed successfully\e[0m";
    sleep 3;
    echo;
    echo "Rebooting the system..."
    sleep 3;
    reboot 5;
else
    SNAP_STATUS=$(jq '.status' /root/.snapstatus.json 2>/dev/null)
    echo -e "\e[1;31mAn error occurred in the update\e[0m";
    sleep 3;
    echo "Don't worry. We are returning the server to its pre-upgrade state.";
    echo "Remember to turn on the server after the restore process.";
    sleep 3;
    apt-get install --reinstall libc6 > /dev/null 2>&1;
    echo "Deploying Snapshot...";
    echo;
    wget --header="Content-Type: application/json" \
        --header="Authorization: Bearer $API_KEY" \
        --post-data='{"linode_id":'"$LINODE_ID"',"overwrite":true}' \
        -O /root/.snaprestore.json \
        https://api.linode.com/v4/linode/instances/"$LINODE_ID"/backups/"$SNAP_ID"/restore > /dev/null 2>&1;
fi
