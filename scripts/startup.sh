#!/bin/bash
set -e

### UPDATE ALL PACKAGES ###
sudo yum update -y

### SETUP GOOGLE CLOUD SDK
curl -o /home/ec2-user/google-cloud-sdk-210.0.0-linux-x86_64.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-210.0.0-linux-x86_64.tar.gz
tar -zxf /home/ec2-user/google-cloud-sdk-210.0.0-linux-x86_64.tar.gz
/home/ec2-user/google-cloud-sdk/install.sh -q
source /home/ec2-user/google-cloud-sdk/path.bash.inc
echo "source /home/ec2-user/google-cloud-sdk/path.bash.inc" >> ~/.bashrc
/home/ec2-user/google-cloud-sdk/bin/gcloud auth activate-service-account --key-file=./google_application_credentials.json

### SETUP MYSQL
mkdir -p /home/ec2-user/mysql_installation_files

curl -o /home/ec2-user/mysql_installation_files/MySQL-client.rpm ${mysql_client_url}
curl -o /home/ec2-user/mysql_installation_files/MySQL-server.rpm ${mysql_server_url}
curl -o /home/ec2-user/mysql_installation_files/MySQL-shared.rpm ${mysql_shared_url}

sudo yum install -y perl-Data-Dumper
sudo yum install -y /home/ec2-user/mysql_installation_files/MySQL-shared.rpm
sudo yum install -y /home/ec2-user/mysql_installation_files/MySQL-server.rpm
sudo yum install -y /home/ec2-user/mysql_installation_files/MySQL-client.rpm

# Remove default my.cnf
sudo rm -rf /usr/my.cnf
cat <<EOF | sudo tee /etc/my.cnf > /dev/null
!includedir /etc/my.cnf.d
EOF

# Write a my.cnf
cat <<EOF | sudo tee /etc/my.cnf.d/custom.cnf > /dev/null
[mysqldump]
max-allowed-packet             = 1073741824

[mysql]

# CLIENT #
port                           = 3306
socket                         = /var/lib/mysql/mysql.sock

max-allowed-packet             = 1073741824

[mysqld]

# GENERAL #
user                           = mysql
default-storage-engine         = InnoDB
socket                         = /var/lib/mysql/mysql.sock
pid-file                       = /var/lib/mysql/mysql.pid
server-id                      = 1337

# MyISAM #
key-buffer-size                = 32M
myisam-recover-options         = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 1073741824
max-connect-errors             = 1000000

# DATA STORAGE #
datadir                        = /var/lib/mysql/

# GTID #
gtid_mode                      = ON
enforce-gtid-consistency       = ON

# BINARY LOGGING #
log-bin                        = /var/lib/mysql/mysql-bin
log-slave-updates              = ON
expire-logs-days               = 14
sync-binlog                    = 1
binlog-format                  = ROW

# CACHES AND LIMITS #
tmp-table-size                 = 32M
max-heap-table-size            = 32M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = 500
thread-cache-size              = 50
open-files-limit               = 65535
table-definition-cache         = 4096
table-open-cache               = 10240

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = 256M
innodb-flush-log-at-trx-commit = 1
innodb-file-per-table          = 1
innodb-buffer-pool-size        = 6G

# CHARACTER SET #
character-set-server           = utf8
collation-server               = utf8_general_ci

# LOGGING #
log-error                      = /var/lib/mysql/mysql-error.log
log-queries-not-using-indexes  = 0
slow-query-log                 = 0
slow-query-log-file            = /var/lib/mysql/mysql-slow.log
EOF

cat <<EOF | sudo tee /etc/my.cnf.d/databases.cnf > /dev/null
[mysqld]
${databases_rep_wild}
EOF

# Initialize MySQL
sudo mysql_install_db

# Start MySQL (also on startup)
sudo chkconfig mysql
sudo /etc/init.d/mysql start

# Change root password
mysqladmin -u root --password=$(sudo cat /root/.mysql_secret | rev | cut -d' ' -f1 | rev) password "${intermediate_root_password}"

# Create replication user
mysql -u root --password="${intermediate_root_password}" -e "CREATE USER '${replication_username}'@'%' IDENTIFIED BY '${replication_password}'"
mysql -u root --password="${intermediate_root_password}" -e "GRANT REPLICATION SLAVE ON *.* TO '${replication_username}'@'%'"
mysql -u root --password="${intermediate_root_password}" -e "FLUSH PRIVILEGES"
