# Migrating AWS RDS/Aurora to Google CloudSQL

This repo holds a terraform project that we use to move/replicate databases from AWS Aurora to Google CloudSQL.
In order for this to work we need a patched version of MySQL, more documentation on that is in [BUILDING_MYSQL.md](BUILDING_MYSQL.md).

## Preparation

* Build the patched version of MySQL, see [BUILDING_MYSQL.md](BUILDING_MYSQL.md) for instructions.
* Make sure `log_bin` is turned on in RDS and binlog_format is set to `ROW` (note, you will have to reboot the machine after changing this)
* Login to RDS, and make sure that we have enough retention (_enough retention means: at least the time it takes to restore the full DB to AWS/GCP + a bit extra_) by running:

  ```
  CALL mysql.rds_set_configuration('binlog retention hours', 24);
  CALL mysql.rds_show_configuration;
  ```

* Create 2 database users in the RDS instance, one for replication and one for doing MySQL backups
  * Create the replication user by changing & running:

    ```
    CREATE USER 'replication user name'@'%' IDENTIFIED BY 'random password'
    GRANT REPLICATION SLAVE ON *.* TO 'replication user name'@'%'
    ```

  * Create the backup user by changing & running:

    ```
    CREATE USER 'backup user name'@'%' IDENTIFIED BY 'random password'
    GRANT SELECT, REPLICATION CLIENT ON *.* TO 'backup user name'@'%'
    ```

* Make a snaphot of the RDS DB and restore it to a new instance
* After it's up (that can take a while), change the instance and configure:
  * The security_group
  * The cluster option group to the same group as the original instance
  * The instance option group to the same group as the original instance
  * Apply immediately and wait for it to say 'pending-reboot' and reboot the machine
* Duplicate `terraform.tfvars.example` and fill in the variables.

## Starting the replication

* Run `terraform apply` to create everything
* Now login to the AWS intermediate machine (the IP is in the terraform output) and run the migration script.
  This script will create backups to the intermediate and to a Google Storage Bucket which can be used to fill the database.

  Running the script automagically enables replication between RDS and the intermediate, and it will give you instructions on how to setup the Google Cloud SQL migration.
  It will post some warnings about passwords on the commandline and partial dumps and GTID's, these can be ignored.

  ```
  ssh ec2-user@<ip>
  screen
  # in the screen:
  /home/ec2-user/backup_to_intermediate

  ```
