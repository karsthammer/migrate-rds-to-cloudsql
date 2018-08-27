# Configure AWS
provider "aws" {
  region = "${var.aws_region}"
}

# Configure Google
provider "google" {
  project = "${var.google_project}"
  region  = "${var.google_region}"
}

# Generate a random name (for naming things obviously)
resource "random_pet" "amazing" {}

# Create a new security group in AWS
resource "aws_security_group" "db_migration" {
  name        = "${random_pet.amazing.id}"
  description = "Allow traffic for DB migration"
  vpc_id      = "${var.aws_vpc_id}"
}

# Add a rule to the security group to allow SSH access
# We need this to be able to connect to the machine and for debugging purposes
resource "aws_security_group_rule" "allow_ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = "${var.intermediate_ssh_allowed_ip_ranges}"
  description = "Allow SSH traffic for debugging"

  security_group_id = "${aws_security_group.db_migration.id}"
}

# Add a rule to the security group to allow MySQL access from Google
# Google needs this to start the replication
# This is empty on the initial run, because we only know the IP when we setup
# the replication in GCP
resource "aws_security_group_rule" "allow_sql_from_google" {
  count       = "${var.google_replication_ip == "" ? 0 : 1}"
  type        = "ingress"
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["${var.google_replication_ip}/32"]
  description = "Allow MySQL traffic from Google for replication"

  security_group_id = "${aws_security_group.db_migration.id}"
}

# Reserve a static IP for the AWS machine, we cannot change the IP Google
# replicates from later on, so we need a static IP to be safe from IP changes
# on reboots etc.
resource "aws_eip" "db_migration" {
  vpc = true
}

# Create a storage bucket in Google. We put the file Google needs to read the
# intial DB contents from in here later on
resource "google_storage_bucket" "database" {
  name          = "${random_pet.amazing.id}"
  location      = "${var.google_region}"
  force_destroy = true
}

# Create a service account in Google to allow the AWS machine to use gsutil
# to copy the DB dump to the storage bucket
resource "google_service_account" "databasedump" {
  account_id   = "${random_pet.amazing.id}"
  display_name = "Database migration - ${random_pet.amazing.id}"
}

# Generate a private_key for the google service account
resource "google_service_account_key" "databasedump" {
  service_account_id = "${google_service_account.databasedump.name}"
}

# Assign rights to the service account
resource "google_storage_bucket_iam_member" "databasedump" {
  bucket = "${google_storage_bucket.database.name}"
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.databasedump.email}"
}

# Generate a random password for the intermediate's root user
resource "random_string" "intermediate_root_password" {
  length  = 12
  special = false
}

# Generate a random username for the intermediate's replica user
resource "random_pet" "intermediate_replication_username" {
  length = 2
}

# Generate a random password for the intermediate's replica password
resource "random_string" "intermediate_replication_password" {
  length  = 12
  special = false
}

locals {
  pet_length           = "${length(random_pet.intermediate_replication_username.id) > 16 ? 16 : length(random_pet.intermediate_replication_username.id)}"
  replication_username = "${substr(random_pet.intermediate_replication_username.id, 0, local.pet_length)}"
}

# Read the startup.sh script and interpolate all the variables,
# this script is later copied to the AWS machine and used as a startup script
# on the first provision.
data "template_file" "startup_script" {
  template = "${file("scripts/startup.sh")}"

  vars {
    intermediate_root_password = "${random_string.intermediate_root_password.result}"
    replication_username       = "${local.replication_username}"
    replication_password       = "${random_string.intermediate_replication_password.result}"
    mysql_client_url           = "${var.mysql_client_url}"
    mysql_server_url           = "${var.mysql_server_url}"
    mysql_shared_url           = "${var.mysql_shared_url}"
    databases_rep_wild         = "${join("\n", formatlist("replicate-wild-do-table=%s.%%", var.databases))}"
  }
}

data "template_file" "replication_script" {
  template = "${file("scripts/start_replication.sh")}"

  vars {
    intermediate_root_password = "${random_string.intermediate_root_password.result}"
    replication_username       = "${local.replication_username}"
    replication_password       = "${random_string.intermediate_replication_password.result}"
    databases_space_sep        = "${join(" ", var.databases)}"
    rds_snapshot_instance      = "${var.rds_snapshot_instance}"
    rds_original_instance      = "${var.rds_original_instance}"
    rds_backup_username        = "${var.rds_backup_username}"
    rds_backup_password        = "${var.rds_backup_password}"
    rds_replication_username   = "${var.rds_replication_username}"
    rds_replication_password   = "${var.rds_replication_password}"
    gcs_bucket                 = "${google_storage_bucket.database.name}"
    instance_public_ip         = "${aws_eip.db_migration.public_ip}"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  owners = ["137112412989"] # Amazon
}

# Create the AWS instance we need as an intermediate MySQL server
resource "aws_instance" "db_migration" {
  ami               = "${data.aws_ami.amazon_linux.id}"
  instance_type     = "${var.intermediate_instance_type}"
  availability_zone = "${var.rds_original_zone}"          # For best performance, use the same zone as the RDS machine
  key_name          = "${var.aws_key_name}"

  # We assign 2 security groups
  #  1. A security group that is able to connect to RDS
  #  2. The security group we just created which allows access from the IP's specified and Google Cloud
  vpc_security_group_ids = [
    "${var.aws_security_group_id}",
    "${aws_security_group.db_migration.id}",
  ]

  subnet_id = "${var.aws_subnet_id}"

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "${var.intermediate_disk_size}"
    delete_on_termination = true
  }

  # Connect as ec2-user
  connection {
    user = "ec2-user"
  }

  # Put the rendered version of mysql.sh on the machine
  provisioner "file" {
    content     = "${data.template_file.startup_script.rendered}"
    destination = "/home/ec2-user/setup-script"
  }

  # Put the rendered version of mysql.sh on the machine
  provisioner "file" {
    content     = "${data.template_file.replication_script.rendered}"
    destination = "/home/ec2-user/start_replication"
  }

  # Put the google private key on the machine
  provisioner "file" {
    content     = "${base64decode(google_service_account_key.databasedump.private_key)}"
    destination = "/home/ec2-user/google_application_credentials.json"
  }

  # Make the setup-script executable
  # and run it
  # This only happens on provisioning, so only the first time the machine boots
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ec2-user/setup-script",
      "chmod +x /home/ec2-user/start_replication",
      "/home/ec2-user/setup-script > /home/ec2-user/setup-script.log",
    ]
  }

  tags {
    Name = "${random_pet.amazing.id}"
  }
}

# Assign the static IP to the AWS instance
resource "aws_eip_association" "db_migration" {
  instance_id   = "${aws_instance.db_migration.id}"
  allocation_id = "${aws_eip.db_migration.id}"
}

# Output the external IP that you can use to ssh into the machine
output "db_migration_ip" {
  value = "${aws_eip.db_migration.public_ip}"
}

output "intermediate_root_password" {
  value = "${random_string.intermediate_root_password.result}"
}

output "intermediate_replication_username" {
  value = "${local.replication_username}"
}

output "intermediate_replication_password" {
  value = "${random_string.intermediate_replication_password.result}"
}
