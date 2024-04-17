#!/bin/bash

set -e
BASE_DIR="/frpc"
INSTALL_DIR="$BASE_DIR/install"
MERLIN_NETWORK_FILE="$BASE_DIR/.merlin_network"
URL_SUFFIX="https://merlin-chain-1317083764.cos.ap-singapore.myqcloud.com"
URL_DOCKER_COMPOSE_YAML="$URL_SUFFIX/validator/docker-compose.yml"
URL_INIT_PROVER_DB_SQL="$URL_SUFFIX/validator/init_prover_db.sql"
URL_NODE_CONFIG_TOML="$URL_SUFFIX/validator/node.config.toml"
URL_TESTNET_NODE_CONFIG_TOML="$URL_SUFFIX/validator/testnet-node.config.toml"
URL_PROVER_CONFIG_JSON="$URL_SUFFIX/validator/prover.config.json"
URL_SNAPSHOT_RESTORE_TOML="$URL_SUFFIX/validator/snapshot_restore.toml"
URL_STATE_DB_INDEX_SQL="$URL_SUFFIX/validator/state_db_index.sql"

init() {
    if [ ! -f $MERLIN_NETWORK_FILE ]; then
        echo "ERROR: .merlin_network file doesn't exist, please deploy first"
        exit 1
    fi
    NETWORK=`cat $DEPLOYMENT_MODE_FILE`
}

update_config() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')]----- Update config -----"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] 1. download config files"
    curl -fsSL $URL_DOCKER_COMPOSE_YAML -o docker-compose.yml && chmod a+r docker-compose.yml
    curl -fsSL $URL_PROVER_CONFIG_JSON -o prover.config.json && chmod a+r prover.config.json
    if [ "$NETWORK" == "mainnet" ]; then
        curl -fsSL $URL_NODE_CONFIG_TOML -o node.config.toml
    else
        curl -fsSL $URL_TESTNET_NODE_CONFIG_TOML -o node.config.toml
    fi
    chmod a+r node.config.toml

    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] 2. stop docker compose service"
    sudo docker compose stop cdk-validium-json-rpc
    sudo docker compose stop cdk-validium-sync
    sudo docker compose stop cdk-validium-pool-db
    sudo docker compose stop cdk-validium-prover

    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] 2. start docker compose service"
    sudo docker compose up -d cdk-validium-prover
    sudo docker compose up -d cdk-validium-pool-db
    sleep 5
    sudo docker compose up -d cdk-validium-sync
    sleep 5
    sudo docker compose up -d cdk-validium-json-rpc
}

# input:
#   $1: command: update_config
run_command() {
    
    if [ "$1" == "update_config" ]; then
        update_config
    else
        echo "ERROR: unsupported command: $1"
        exit 1
    fi
}

# ------------------------------
# main
#
# command: update_config
# ------------------------------
init
run_command {{command}}
