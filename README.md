# mysql_db_backup_script

Quick script to backup a seafile mysql database as separate files, in time stamped directories.

  * Queries mySQL for database names
  * For each database
    * fetches table names, and partition names for partitioned tables
    * Makes a backup directory for each date, and in that, a directory for each database
    * Uses mysqldump to dump the database schema into the database directory
    * Uses mysqldumy to dump just the data, from each table, into a <table>.sql.gz file.
      * Dumps partitioned tables in a file per partition
    * prints of each command, with any error messages, which is dumped into a log file.

## Crontab
Run from crontab, as the seafile user, about an hour before the backups run.
```
30 3,15 * * * /data/bin/db_backup.rb >> /data/db_backup/backup.log 2>&1
```
