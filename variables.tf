variable "aws_region" {
  type = "string"
}

variable "aws_vpc_id" {
  type = "string"
}

variable "aws_subnet_id" {
  type = "string"
}

variable "aws_security_group_id" {
  type = "string"
}

variable "aws_key_name" {
  type = "string"
}

variable "mysql_client_url" {
  type = "string"
}

variable "mysql_server_url" {
  type = "string"
}

variable "mysql_shared_url" {
  type = "string"
}

variable "intermediate_ssh_allowed_ip_ranges" {
  type = "list"

  default = []
}

variable "intermediate_instance_type" {
  type    = "string"
  default = "m5.large"
}

variable "intermediate_disk_size" {
  type    = "string"
  default = "100"
}

variable "databases" {
  type = "list"
}

variable "rds_snapshot_instance" {
  type = "string"
}

variable "rds_original_instance" {
  type = "string"
}

variable "rds_original_zone" {
  type = "string"
}

variable "rds_backup_username" {
  type = "string"
}

variable "rds_backup_password" {
  type = "string"
}

variable "rds_replication_username" {
  type = "string"
}

variable "rds_replication_password" {
  type = "string"
}

variable "google_project" {
  type = "string"
}

variable "google_region" {
  type = "string"
}

variable "google_replication_ip" {
  type    = "string"
  default = ""
}
