#!/bin/bash

set -e

BASE_DIR="/frpc"
INSTALL_DIR="$BASE_DIR/install"
URL_SUFFIX="https://ritchie-demo-1317083764.cos.ap-singapore.myqcloud.com"
URL_DOCKER_COMPOSE_YAML="$URL_SUFFIX/merlin/docker-compose.yml"
URL_INIT_PROVER_DB_SQL="$URL_SUFFIX/merlin/init_prover_db.sql"
URL_NODE_CONFIG_TOML="$URL_SUFFIX/merlin/node.config.toml"
URL_TESTNET_NODE_CONFIG_TOML="$URL_SUFFIX/merlin/testnet-node.config.toml"
URL_PROVER_CONFIG_JSON="$URL_SUFFIX/merlin/prover.config.json"
URL_SNAPSHOT_RESTORE_TOML="$URL_SUFFIX/merlin/snapshot_restore.toml"

NETWORK={{network}}
# NETWORK="mainnet"


init_nvme_disk() {
    echo "===== init_nvme_disk ====="
    # 获取 path to device
    ldisk=$(ls /dev/disk/by-id |grep ldisk)
    device_path=$(readlink -f /dev/disk/by-id/$ldisk)
    sudo mkfs -t ext4 $device_path

    sudo mkdir $BASE_DIR
    sudo mount /dev/vdb $BASE_DIR

    # 获取 UUID
    uuid=$(sudo blkid -o value -s UUID $device_path)
    sudo sh -c "echo \"/dev/disk/by-uuid/$uuid $BASE_DIR ext4 defaults 0 0\" >> /etc/fstab"

    #
    sudo mkdir $BASE_DIR/state_db
    sudo mkdir $BASE_DIR/pool_db
    sudo mkdir $INSTALL_DIR
}

init_env() {
    echo "===== init_env ====="
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo service docker start

    # install golang
    wget https://go.dev/dl/go1.22.1.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.1.linux-amd64.tar.gz
    echo "export GOROOT=/usr/local/go" >> ~/.profile
    echo "export GOPATH=\$HOME/go" >> ~/.profile
    echo "export PATH=\$GOPATH/bin:\$GOROOT/bin:\$PATH" >> ~/.profile
    source ~/.profile

    # download config files
    curl -fsSL $URL_DOCKER_COMPOSE_YAML -o docker-compose.yml
    curl -fsSL $URL_INIT_PROVER_DB_SQL -o init_prover_db.sql
    curl -fsSL $URL_PROVER_CONFIG_JSON -o prover.config.json
    if [ "$NETWORK" == "mainnet" ]; then
        curl -fsSL $URL_NODE_CONFIG_TOML -o node.config.toml
    else
        curl -fsSL $URL_TESTNET_NODE_CONFIG_TOML -o node.config.toml
    fi
}

run_db() {
    echo "===== run_db ====="
    # database server
    sudo docker compose up -d cdk-validium-state-db

    # Snapshot Recovery
    # Install postgresql-client-15
    sudo apt install gnupg2 wget vim -y
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
    sudo apt update -y
    sudo apt install postgresql-client-15 -y

    git clone https://github.com/0xPolygon/cdk-validium-node.git
    cd cdk-validium-node
    go build -o ./build ./cmd

    wget $URL_SNAPSHOT_RESTORE_TOML
    sudo sh -c "echo \"127.0.0.1  zkevm-state-db\" >> /etc/hosts"
    # Download recovery database snapshot
    if [ "$NETWORK" == "mainnet" ]; then
        # Mainnet
        sudo wget -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/state_db.sql.tar.gz &
        sudo wget -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/prover_db.sql.tar.gz &
        wait
        ./build restore --cfg ./snapshot_restore.toml -is $BASE_DIR/install/state_db.sql.tar.gz -ih $BASE_DIR/install/prover_db.sql.tar.gz
    else
        # Testnet
        sudo wget -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/testnet_state_db.sql.tar.gz &
        sudo wget -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/testnet_prover_db.sql.tar.gz &
        wait
        ./build restore --cfg ./snapshot_restore.toml -is $BASE_DIR/install/testnet_state_db.sql.tar.gz -ih $BASE_DIR/install/testnet_prover_db.sql.tar.gz
    fi
}

run_node() {
    echo "===== run_node ====="
    cd -
    if [ "$NETWORK" == "mainnet" ]; then
        wget http://18.167.109.180:8866/merlin/mainnet/genesis.json
    else
        wget http://18.167.109.180:8866/merlin/testnet/genesis.json
    fi

    # sync server
    sudo docker compose up -d cdk-validium-prover
    sudo docker compose up -d cdk-validium-pool-db
    sleep 5
    sudo docker compose up -d cdk-validium-sync

    # RPC Server
    sudo docker compose up -d cdk-validium-prover
    sudo docker compose up -d cdk-validium-pool-db
    sleep 5
    sudo docker compose up -d cdk-validium-json-rpc
}

# ------------------------------
# main
# ------------------------------

if [ "$NETWORK" = "mainnet" ] || [ "$NETWORK" = "testnet" ]; then
    echo "===== Start to deploy $NETWORK ====="
else
    echo "network=$NETWORK is not valid."
    exit 1
fi

init_nvme_disk
init_env
run_db
run_node

echo "===== Finished deploying $NETWORK ====="
