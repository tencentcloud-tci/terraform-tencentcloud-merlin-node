#!/bin/bash

set -e

BASE_DIR="/frpc"
INSTALL_DIR="$BASE_DIR/install"
MERLIN_NETWORK_FILE="$BASE_DIR/.merlin_network"
URL_SUFFIX="https://ritchie-demo-1317083764.cos.ap-singapore.myqcloud.com"
URL_DOCKER_COMPOSE_YAML="$URL_SUFFIX/merlin/docker-compose.yml"
URL_INIT_PROVER_DB_SQL="$URL_SUFFIX/merlin/init_prover_db.sql"
URL_NODE_CONFIG_TOML="$URL_SUFFIX/merlin/node.config.toml"
URL_TESTNET_NODE_CONFIG_TOML="$URL_SUFFIX/merlin/testnet-node.config.toml"
URL_PROVER_CONFIG_JSON="$URL_SUFFIX/merlin/prover.config.json"
URL_SNAPSHOT_RESTORE_TOML="$URL_SUFFIX/merlin/snapshot_restore.toml"

NETWORK={{network}}


init_nvme_disk() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== 1. init_nvme_disk ====="
    # 获取实例类型
    INSTANCE_TYPE=`curl http://metadata.tencentyun.com/latest/meta-data/instance/instance-type`

    # 获取 path to device
    if [ "$INSTANCE_TYPE" == "ITA4.4XLARGE64" ]; then
        ldisk=$(ls /dev/disk/by-id |grep nvme-eui)
        device_path=$(readlink -f /dev/disk/by-id/$ldisk)
    elif [ "$INSTANCE_TYPE" == "IT5.4XLARGE64" ]; then
        ldisk=$(ls /dev/disk/by-id |grep ldisk)
        device_path=$(readlink -f /dev/disk/by-id/$ldisk)
    else
        echo "ERROR: unsupported instance type [$INSTANCE_TYPE]"
        exit 1
    fi

    if mount | grep "$device_path" > /dev/null; then
        echo "$device_path is mounted"
        return
    fi

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
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== 2. init_env ====="
    if ! command -v docker > /dev/null; then
        # install docker
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 2.1 Install docker +++++"
        sudo apt-get -qq update
        sudo apt-get install -y -qq ca-certificates curl > /dev/null
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get -qq update

        sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
        sudo service docker start
    else
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- 2.1 [Skip]Install docker -----"
    fi

    if ! command -v go > /dev/null; then
        # install golang
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 2.2 Install golang +++++"
        wget -q https://go.dev/dl/go1.22.1.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.1.linux-amd64.tar.gz
        echo "export GOROOT=/usr/local/go" >> ~/.bashrc
        echo "export GOPATH=\$HOME/go" >> ~/.bashrc
        echo "export PATH=\$GOPATH/bin:\$GOROOT/bin:\$PATH" >> ~/.bashrc
        source ~/.bashrc
        echo "export GOROOT=/usr/local/go" >> ~/.profile
        echo "export GOPATH=\$HOME/go" >> ~/.profile
        echo "export PATH=\$GOPATH/bin:\$GOROOT/bin:\$PATH" >> ~/.profile
        source ~/.profile
    else
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- 2.2 [Skip]Install golang -----"
    fi

    # download config files
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 2.3 Download config files +++++"
    curl -fsSL $URL_DOCKER_COMPOSE_YAML -o docker-compose.yml && chmod a+r docker-compose.yml
    curl -fsSL $URL_INIT_PROVER_DB_SQL -o init_prover_db.sql && chmod a+r init_prover_db.sql
    curl -fsSL $URL_PROVER_CONFIG_JSON -o prover.config.json && chmod a+r prover.config.json
    if [ "$NETWORK" == "mainnet" ]; then
        curl -fsSL $URL_NODE_CONFIG_TOML -o node.config.toml
    else
        curl -fsSL $URL_TESTNET_NODE_CONFIG_TOML -o node.config.toml
    fi
    chmod a+r node.config.toml
}

run_db() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== 3. run_db ====="
    # database server
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 3.1 Run service cdk-validium-state-db +++++"
    sudo docker compose up --quiet-pull -d cdk-validium-state-db

    # Snapshot Recovery
    # Install postgresql-client-15
    if [ -d "cdk-validium-node" ]; then
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- 3.2 [Skip]Install cdk-validium-node -----"
        cd cdk-validium-node
    else
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 3.2 Install cdk-validium-node +++++"
        sudo apt-get install gnupg2 wget vim -y -qq > /dev/null
        sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
        sudo apt-get -qq update -y
        sudo apt-get install postgresql-client-15 -y -qq > /dev/null

        git clone https://github.com/0xPolygon/cdk-validium-node.git
        cd cdk-validium-node
        go build -o ./build ./cmd > /tmp/go_build 2>&1
        wget -q $URL_SNAPSHOT_RESTORE_TOML
        sudo sh -c "echo \"127.0.0.1  zkevm-state-db\" >> /etc/hosts"
    fi

    # Download recovery database snapshot
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 3.3 Download & import recovery database snapshot +++++"
    if [ "$NETWORK" == "mainnet" ]; then
        # Mainnet
        if [ -f "$INSTALL_DIR/prover_db.sql.tar.gz" ]; then
            echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- [Skip] downloading recovery database snapshot -----"
            ./build restore --cfg ./snapshot_restore.toml -is $INSTALL_DIR/state_db.sql.tar.gz -ih $INSTALL_DIR/prover_db.sql.tar.gz
        else
            sudo wget -q -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/state_db.sql.tar.gz &
            sudo wget -q -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/prover_db.sql.tar.gz &
            wait
            ./build restore --cfg ./snapshot_restore.toml -is $INSTALL_DIR/state_db.sql.tar.gz -ih $INSTALL_DIR/prover_db.sql.tar.gz
        fi
    else
        # Testnet
        if [ -f "$INSTALL_DIR/testnet_prover_db.sql.tar.gz" ]; then
            echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- [Skip] downloading recovery database snapshot -----"
            ./build restore --cfg ./snapshot_restore.toml -is $INSTALL_DIR/testnet_state_db.sql.tar.gz -ih $INSTALL_DIR/testnet_prover_db.sql.tar.gz
        else
            sudo wget -q -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/testnet_state_db.sql.tar.gz &
            sudo wget -q -P $INSTALL_DIR https://merlin-chain-snapshot.s3.ap-east-1.amazonaws.com/testnet_prover_db.sql.tar.gz &
            wait
            ./build restore --cfg ./snapshot_restore.toml -is $INSTALL_DIR/testnet_state_db.sql.tar.gz -ih $INSTALL_DIR/testnet_prover_db.sql.tar.gz
        fi
    fi
}

run_node() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== 4. run_node ====="
    cd -
    if [ "$NETWORK" == "mainnet" ]; then
        wget -q http://18.167.109.180:8866/merlin/mainnet/genesis.json
    else
        wget -q http://18.167.109.180:8866/merlin/testnet/genesis.json
    fi

    # sync server
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 4.1 run sync server +++++"
    sudo docker compose up --quiet-pull -d cdk-validium-prover
    sudo docker compose up --quiet-pull -d cdk-validium-pool-db
    sleep 5
    sudo docker compose up --quiet-pull -d cdk-validium-sync

    # RPC Server
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]+++++ 4.2 run RPC server +++++"
    sudo docker compose up --quiet-pull -d cdk-validium-json-rpc
}

before() {
    if [ "$NETWORK" = "mainnet" ] || [ "$NETWORK" = "testnet" ]; then
        if [ -f $MERLIN_NETWORK_FILE ]; then
            local existing_network=$(cat $MERLIN_NETWORK_FILE)
            if [ "$NETWORK" != $existing_network ]; then
                echo "ERROR: $existing_network(not $NETWORK) node has been deployed"
                exit 1
            else
                echo "INFO: $NETWORK node has already been deployed"
                exit 0
            fi
        fi
        echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== Start to deploy $NETWORK ====="
    else
        echo "ERROR: network=$NETWORK is not valid."
        exit 1
    fi
}

after() {
    local block_number=`curl --location 'http://localhost:8123' -s --header 'Content-Type: application/json' --data '{\
    "jsonrpc": "2.0",\
    "method": "eth_blockNumber",\
    "params": [],\
    "id": 1\
    }' | jq -r '.result' | xargs -I {} printf "%d\n" {}`
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== Block number: $block_number ====="
    sudo sh -c "echo $NETWORK > $MERLIN_NETWORK_FILE"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]===== Finished deploying $NETWORK ====="
}

# ------------------------------
# main
# ------------------------------

before
init_nvme_disk
init_env
run_db
run_node
after
