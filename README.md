# mysql_db_backup_script

Quick script to backup a seafile mysql database as separate files, in time stamped directories.

* Queries mySQL for database names
* For each database
  * fetches table names, and partition names for partitioned tables
  * Makes a backup directory for each date, and in that, a directory for each database
  * Uses mysqldump to dump the database schema into the database directory
  * Uses mysqldumy to dump just the data, from each table, into a <table>.sql.gz file.
    * Dumps partitioned tables in a file per partition
  * Keeps a log of each command, with any error messages


