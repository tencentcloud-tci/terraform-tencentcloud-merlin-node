# Merlin Terraform Stack for external node deployment
This solution deploys a Terraform stack for Merlin nodes on Tencent Cloud. It uses CVM as main compute service alongside other necessary resources.

Merlin documentation: https://docs.merlinchain.io/merlin-docs/developers/external-node-deployment

# Pre-requisites
## Tencent Cloud Account Creation and Setup
Please follow the below procedures to set-up your Tencent Cloud Account
 - Contact our partner( [telegram](https://t.me/mizukate) ) to get an account
 - Better to follow [best practices](https://www.tencentcloud.com/document/product/598/10592) for enhancing the security

## Deployment Configuration
The deployment is made with terraform, directly through the API of the Tencent Cloud Account created in the step above. To achieve the deployment, the environment must be set-up. Here are the steps:

### Step1 - Generate new Tencent Cloud API keys
For root account: https://www.tencentcloud.com/document/product/598/34228

For sub-account: https://www.tencentcloud.com/document/product/598/32675

### Step2 - Install Terraform
Install terraform: https://developer.hashicorp.com/terraform/install

### Step3 - Configure Tencent Cloud API keys for Terraform
Follow the instructions in section "Environment variables": https://registry.terraform.io/providers/tencentcloudstack/tencentcloud/latest/docs

# Solution Deployment
## Quick start
Here we create a new dir `demo`.

File structure:
```
demo
└── main.tf
```

The content of `main.tf`:
```hcl
module "merlin" {
  source             = "tencentcloud-tci/merlin-node/tencentcloud"
  az                 = "ap-singapore-3"
  instance_type      = "ITA4.4XLARGE64"
  create_tat_command = true #set 'false' only if the commands are already deployed
  merlin_network     = "mainnet" #2 options: mainnet, testnet
}
```

Having the configuration done, continue with these commands:
- `terraform init`
- `terraform plan`
- `terraform apply` select yes, enter

## Main parameters
The key parameters are
- `az` is the availability zone within the selected region, [az list](https://www.tencentcloud.com/document/product/416/6479?lang=en)
- `instance_type` is the CVM instance type, currently it only supports serials: IT5, ITA4
- `create_tat_command` set 'false' only if the commands are already deployed (if previous/paralel deployment existed)
- `merlin_network` choose between mainnet, testnet. This selection will switch the Merlin network.

## Deployment details
We mount the local NVMe SSD disk as `/frpc`.
- `/frpc/install` for snapshot data files: prover_db.sql.tar.gz, state_db.sql.tar.gz
- `/frpc/pool_db` used for db data of merlin-pool-db
- `/frpc/state_db` used for db data of merlin-state-db

The root directory for installation is `/home/ubuntu`

We use the [TAT commands](https://www.tencentcloud.com/document/product/1147/46048?lang=en&pg=) to run installation script on CVM instance.

# Managing the node
## Logging
## Verify operation

