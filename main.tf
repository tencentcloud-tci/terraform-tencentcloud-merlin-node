data "tencentcloud_images" "this" {
  image_type       = ["PUBLIC_IMAGE"]
  image_name_regex = "^Ubuntu Server 22\\.04.*"
}

locals {
  use_existing_vpc    = var.vpc_id != ""
  use_existing_subnet = var.subnet_id != ""
  command_name        = "merlin-node-installer"
}

resource "tencentcloud_vpc" "this" {
  count      = local.use_existing_vpc ? 0 : 1
  cidr_block = var.vpc_cidr
  name       = format("%s-vpc", var.suffix)
  tags       = var.tags
}

resource "tencentcloud_subnet" "this" {
  count             = local.use_existing_subnet ? 0 : 1
  vpc_id            = local.use_existing_vpc ? var.vpc_id : tencentcloud_vpc.this.0.id
  cidr_block        = var.subnet_cidr
  name              = format("%s-subnet", var.suffix)
  availability_zone = var.az
}

resource "tencentcloud_instance" "this" {
  instance_name           = format("%s-node", var.suffix)
  availability_zone       = var.az
  instance_type           = var.instance_type
  image_id                = data.tencentcloud_images.this.images.0.image_id
  system_disk_type        = "CLOUD_PREMIUM"
  system_disk_size        = 50
  vpc_id                  = local.use_existing_vpc ? var.vpc_id : tencentcloud_vpc.this.0.id
  subnet_id               = local.use_existing_subnet ? var.subnet_id : tencentcloud_subnet.this.0.id
  orderly_security_groups = var.sg_ids

  allocate_public_ip         = true
  internet_max_bandwidth_out = 50

  tags = var.tags

  # waiting for the TAT agent installation
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

data "tencentcloud_tat_command" "this" {
  command_type = "SHELL"
  created_by   = "USER"
  command_name = local.command_name
  lifecycle {
    postcondition {
      condition     = anytrue([!var.create_tat_command && self.command_set != null, var.create_tat_command])
      error_message = "Please check the TAT command, ther is no required one. Try to set create_tat_command=true."
    }
  }
}

resource "tencentcloud_tat_command" "this" {
  count             = var.create_tat_command ? 1 : 0
  command_name      = local.command_name
  content           = file(join("", [path.module, "/scripts/install.sh"]))
  description       = "Deploy merlin node"
  command_type      = "SHELL"
  timeout           = 86000
  username          = "ubuntu"
  working_directory = "/home/ubuntu"
  enable_parameter  = true
  default_parameters = jsonencode({
    "network" : ""
  })
}

resource "tencentcloud_tat_invocation_invoke_attachment" "this" {
  command_id        = var.create_tat_command ? tencentcloud_tat_command.this[0].id : data.tencentcloud_tat_command.this.command_set[0].command_id
  instance_id       = tencentcloud_instance.this.id
  username          = "ubuntu"
  timeout           = 86000
  working_directory = "/home/ubuntu"
  parameters = jsonencode({
    network = var.merlin_network
  })

  depends_on = [
    tencentcloud_instance.this
  ]
}
