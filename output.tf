output "CVM_instances" {
  value       = tencentcloud_instance.this[*].id
  description = "CVM instance id list"
}
