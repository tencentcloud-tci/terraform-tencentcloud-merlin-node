#!/bin/bash
BASE_DIR="/frpc"
# 获取实例类型
INSTANCE_TYPE=`curl http://metadata.tencentyun.com/latest/meta-data/instance/instance-type`

# 获取 path to device
if [[ ${INSTANCE_TYPE:0:3} == "ITA" ]]; then
    ldisk=$(ls /dev/disk/by-id | grep nvme-eui | head -n 1)
    device_path=$(readlink -f /dev/disk/by-id/$ldisk)
elif [ ${INSTANCE_TYPE:0:3} == "IT5" ]; then
    ldisk=$(ls /dev/disk/by-id | grep ldisk | head -n 1)
    device_path=$(readlink -f /dev/disk/by-id/$ldisk)
else
    echo "ERROR: unsupported instance type [$INSTANCE_TYPE]"
    exit 1
fi

mkfs -t ext4 $device_path
mkdir $BASE_DIR
mount $device_path $BASE_DIR

# 获取 UUID
uuid=$(blkid -o value -s UUID $device_path)
sh -c "echo \"/dev/disk/by-uuid/$uuid $BASE_DIR ext4 defaults 0 0\" >> /etc/fstab"
