# MySQL replication setup

Many thanks to this article from Booking.com: https://medium.com/booking-com-infrastructure/mysql-5-6-gtids-evaluation-and-online-migration-139693719ff2

We use a patched version of MySQL as an inbetween slave/master machine. This allows
us to have the following setup:

```
        |---------------------------|
        |           Aurora          |
        |             --            |
        |  non GTID capable master  |
        |---------------------------|
                     |
     |---------------------------------|
     |        Our patched MySQL        |
     |           -----------           |
     | This acts as a slave to aurora  |
     |   and acts as a GTID capable    |
     |       master for Cloud SQL      |
     |---------------------------------|
                     |
          |------------------------|
          |    Google Cloud SQL    |
          |       ----------       |
          | Acts as a slave to our |
          |  patched MySQL so we   |
          | can use standard MySQL |
          |      replication       |
          |------------------------|
```

## Installing

We have built a version of MySQL that includes a patch that makes this setup
possible.

This guide is based on the latest available version of MySQL 5.6, currently 5.6.41.

## Building a new copy

Start a Linux VM and download a source RPM from the MySQL
website, it's under the *source code* downloads section and put it in your
home directory.

E.g. `wget https://dev.mysql.com/get/Downloads/MySQL-5.6/MySQL-5.6.41-1.el6.src.rpm`

Install the source rpm by running `rpm -i <your-rpm.rpm>`, this will create a
folder in your home directory called `rpmbuild`. The tree looks like this:

```
rpmbuild/
├── SOURCES
│   └── mysql-5.6.41.tar.gz
└── SPECS
    └── mysql.spec
```

### Applying the patch

* Extract the `mysql-5.6.41.tar.gz` file, `tar -zxf mysql-5.6.41.tar.gz`
* Open the `mysql-5.6.41/sql/rpl_slave.cc` file, and look for the following piece of code
  in the `get_master_version_and_clock()` function.

  ```
  if (mi->master_gtid_mode > gtid_mode + 1 ||
    gtid_mode > mi->master_gtid_mode + 1)
  {
    mi->report(ERROR_LEVEL, ER_SLAVE_FATAL_ERROR,
               "The slave IO thread stops because the master has "
               "@@GLOBAL.GTID_MODE %s and this server has "
               "@@GLOBAL.GTID_MODE %s",
               gtid_mode_names[mi->master_gtid_mode],
               gtid_mode_names[gtid_mode]);
    DBUG_RETURN(1);
  }
  ```

  This piece of code needs to be commented out (using `/* */`)

* Now, zip everything back together:

  ```
  rm mysql-5.6.41.tar.gz
  tar -czf mysql-5.6.41.tar.gz mysql-5.6.41/
  rm -rf mysql-5.6.41/
  ```

* And install the build dependencies:

  ```
  sudo yum install -y rpm-build gcc gperf ncurses-devel zlib-devel gcc-c++ libaio-devel cmake openssl-devel cyrus-sasl-devel openldap-devel perl-Data-Dumper perl-JSON
  ```

* Now build a new RPM (this will take a while):

  ```
  rpmbuild -ba SPECS/mysql.spec
  ```

* Fetch the new RPMs (there are several) from the `rpmbuild/RPMS` directory
  and store them in a place that will be accessible from the AWS machine we will
  be using to replicate.
