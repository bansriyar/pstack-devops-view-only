#!/usr/bin/env bash

mkfs -t ext4 /dev/xvdg
mkdir /var/lib/elasticsearch
mount /dev/xvdg /var/lib/elasticsearch
echo /dev/xvdg  /var/lib/elasticsearch ext4 defaults,nofail 0 2 >> /etc/fstab