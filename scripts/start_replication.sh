#!/bin/bash
set -e

# CHECK IF WE'RE RUNNING INSIDE SCREEN FOR SELF PROTECTION
if [ -z "$STY" ]; then
  echo "Please run this script inside screen"
  exit 1
fi

# Query master status
echo "Getting master status"
echo "What binlog file did you recover from?"
read FILE
echo "What binlog position did you recover from?"
read POS

echo "FOUND BINLOG: $FILE"
echo "FOUND BINLOG POSITION: $POS"

# Get list of all databases
DATABASES="${databases_space_sep}"
if [[ -z "$DATABASES" ]]; then
  DATABASES=$(mysql -h ${rds_snapshot_instance} -u ${rds_backup_username} --password=${rds_backup_password} -NBe 'show schemas' | grep -wv 'mysql\|information_schema\|performance_schema')
fi

# Dump database
echo "Copying databases to intermediate instance"
mysqldump -h ${rds_snapshot_instance} -u ${rds_backup_username} --password=${rds_backup_password} --databases $DATABASES --order-by-primary --skip-add-drop-table --skip-add-locks --skip-disable-keys --skip-set-charset --no-autocommit --default-character-set=utf8 --single-transaction | mysql -u root --password=${intermediate_root_password}

# Set master status
echo "Setting master status"
mysql -u root --password=${intermediate_root_password} -e "CHANGE MASTER TO MASTER_HOST = '${rds_original_instance}', MASTER_PORT = 3306, MASTER_USER = '${rds_replication_username}', MASTER_PASSWORD = '${rds_replication_password}', MASTER_LOG_FILE = '$FILE', MASTER_LOG_POS = $POS;"

# Dump to GCLOUD bucket (please note: we dump from the intermediate here because then we have GTIDs)
echo "Backing up to GCLOUD bucket ${gcs_bucket}"
mysqldump -u root --password=${intermediate_root_password} --databases $DATABASES --order-by-primary --skip-add-drop-table --skip-add-locks --skip-disable-keys --skip-set-charset --no-autocommit --default-character-set=utf8 --single-transaction --set-gtid-purged=on --master-data=1 | gzip | gsutil cp - gs://${gcs_bucket}/dump.sql.gz

# Start replication
echo "Starting replication to intermediate"
mysql -u root --password=${intermediate_root_password} -e "START SLAVE;"

# Everything done
echo "Everything is done!"
echo "Please go to Google Cloud and click the Migrate button in Cloud SQL"
echo "You will need to provide the following parameters:"
echo "--------------------------------------------------"
echo "Name of data source: <choose something unique within the google project>"
echo "Public IP address: ${instance_public_ip}"
echo "Port number of source: 3306"
echo "MySQL replication username: ${replication_username}"
echo "MySQL replication password: ${replication_password}"
echo "--------------------------------------------------"
echo "SQL Dump file: gs://${gcs_bucket}/dump.sql.gz"
echo "--------------------------------------------------"
echo "Database flags:"
echo "  max_allowed_packet = 1073741824"
echo "--------------------------------------------------"
echo ""
echo "When Google Cloud provides you with the IP, update the"
echo "google_replication_ip variable in terraform's"
echo "terraform.tfvars file and run terraform apply again."
echo ""
echo "After terraform is finished Google Cloud should be able"
echo "to connect."
