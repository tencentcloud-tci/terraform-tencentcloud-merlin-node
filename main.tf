data "tencentcloud_images" "this" {
  image_type       = ["PUBLIC_IMAGE"]
  image_name_regex = "^Ubuntu Server 22\\.04.*"
}

locals {
  use_existing_vpc       = var.vpc_id != ""
  use_existing_subnet    = var.subnet_id != ""
  installer_command_name = "merlin-node-installer"
  tool_command_name      = "merlin-node-tool"
}

resource "tencentcloud_vpc" "this" {
  count      = local.use_existing_vpc ? 0 : 1
  cidr_block = var.vpc_cidr
  name       = "${var.prefix}-vpc"
  tags       = var.tags
}

resource "tencentcloud_subnet" "this" {
  count             = local.use_existing_subnet ? 0 : 1
  vpc_id            = local.use_existing_vpc ? var.vpc_id : tencentcloud_vpc.this.0.id
  cidr_block        = var.subnet_cidr
  name              = "${var.prefix}-subnet"
  availability_zone = var.az
}

resource "tencentcloud_security_group" "this" {
  name        = "${var.prefix}-sg"
  description = "A security group used by Merlin chain nodes"
  tags        = var.tags
}

resource "tencentcloud_security_group_lite_rule" "this" {
  security_group_id = tencentcloud_security_group.this.id
  ingress = [
    "DROP#0.0.0.0/0#5432,5433#TCP",
    "ACCEPT#0.0.0.0/0#50061,50071#TCP",
    "ACCEPT#0.0.0.0/0#9091#TCP",
    "ACCEPT#81.69.102.0/24#22#TCP",
    "ACCEPT#106.55.203.0/24#22#TCP",
    "ACCEPT#101.33.121.0/24#22#TCP",
    "ACCEPT#101.32.250.0/24#22#TCP",
    "ACCEPT#175.27.43.0/24#22#TCP",
    "ACCEPT#11.163.0.0/16#22#TCP",
    "ACCEPT#0.0.0.0/0#ALL#ICMP",
  ]
  egress = [
    "ACCEPT#0.0.0.0/0#ALL#ALL",
  ]
}

resource "tencentcloud_instance" "this" {
  count                   = var.instance_count
  instance_name           = "${var.prefix}-node-${count.index}"
  availability_zone       = var.az
  instance_type           = var.instance_type
  image_id                = data.tencentcloud_images.this.images.0.image_id
  system_disk_type        = "CLOUD_PREMIUM"
  system_disk_size        = 50
  vpc_id                  = local.use_existing_vpc ? var.vpc_id : tencentcloud_vpc.this.0.id
  subnet_id               = local.use_existing_subnet ? var.subnet_id : tencentcloud_subnet.this.0.id
  orderly_security_groups = concat([tencentcloud_security_group.this.id], var.sg_ids)

  allocate_public_ip                      = true
  internet_max_bandwidth_out              = 50
  instance_charge_type                    = var.instance_charge_type
  instance_charge_type_prepaid_period     = var.instance_charge_type == "PREPAID" ? 1 : null
  instance_charge_type_prepaid_renew_flag = var.instance_charge_type == "PREPAID" ? "NOTIFY_AND_AUTO_RENEW" : null

  tags = var.tags

  user_data = base64encode(file("${path.module}/scripts/mount_nvme.sh"))

  # waiting for the TAT agent installation
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

data "tencentcloud_tat_command" "this" {
  command_type = "SHELL"
  created_by   = "USER"
  command_name = local.installer_command_name
  lifecycle {
    postcondition {
      condition     = anytrue([!var.create_tat_command && self.command_set != null, var.create_tat_command])
      error_message = "Please check the TAT command, ther is no required one. Try to set create_tat_command=true."
    }
  }
}

resource "tencentcloud_tat_command" "this" {
  count             = var.create_tat_command ? 1 : 0
  command_name      = local.installer_command_name
  content           = file("${path.module}/scripts/install.sh")
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

resource "tencentcloud_tat_command" "tool" {
  count             = var.create_tat_command ? 1 : 0
  command_name      = local.tool_command_name
  content           = file("${path.module}/scripts/tool.sh")
  description       = "Operation tool for merlin node"
  command_type      = "SHELL"
  timeout           = 3600
  username          = "ubuntu"
  working_directory = "/home/ubuntu"
  enable_parameter  = true
  default_parameters = jsonencode({
    "command" : ""
  })
}

resource "tencentcloud_tat_invocation_invoke_attachment" "this" {
  count             = length(tencentcloud_instance.this)
  command_id        = var.create_tat_command ? tencentcloud_tat_command.this[0].id : data.tencentcloud_tat_command.this.command_set[0].command_id
  instance_id       = tencentcloud_instance.this[count.index].id
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
