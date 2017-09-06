#!/usr/local/bin/ruby
require 'wikk_sql'            #From the wikk_sql gem
require 'wikk_configuration'  #From the wikk_configuration gem

#Read the seafile.conf file, to get the seafile password
def load_config
  config = {}
  File.open('/data/seafile-app/conf/seafile.conf', 'r') do |fd|
    fd.each_line do |l|
      case l.strip!
      when /^password/; config['key'] = l.split('=')[1].strip
      when /^user/; config['dbuser'] = l.split('=')[1].strip
      when /^host/; config['host'] = l.split('=')[1].strip
      when /^port/; config['port'] = l.split('=')[1].strip
      when /^db_name/; config['db'] = l.split('=')[1].strip
      end
    end
  end
  @config = WIKK::Configuration.new(config)
end

#Make the backup directory for this days database dump.
def mk_backup_directory(db_name:)
  return if ARGV[0] == '-d'
  dir = "/data/db_backup/backup_#{Time.new.strftime("%Y-%m-%d")}/#{db_name}"
  `/bin/mkdir -p #{dir}`
  Dir.chdir(dir)
end

#Run the command, printing the command to stdout, so we can log it
def command_with_echo(cmd)
  puts "#{Time.new.strftime("%Y-%m-%d %H:%M:%S")} #{cmd.gsub(/\-p[^\s]+\s/, '-pXXXXXX ')}" #Bit of a hack :)
  return if ARGV[0] == '-d'
  #`time -f '\t%E real' #{cmd}`
  `#{cmd}`
  puts "Completed with exit code: #{$?}" if $? != 0
end

#Dump the database schema as a separate file.
def save_schema(db_name:)
  #Record Database Schema.
  command_with_echo "/usr/bin/mysqldump  -u #{@config.dbuser} -p#{@config.key} --opt --no-data -h #{@config.host} #{db_name} > #{db_name}.schema.sql"
end

#Discover the databases 
def discover_databases
  @databases = []
  WIKK::SQL::each_row(@config, "show databases") do |row|
    @databases << row[0]
  end
end

#Read the table names from the database, so we can output tables into individual files.
#Also check to see if there are partitioned tables, so these can be dumped as separate files.
def discover_tables(db_name:)
  #Tables to dump, from listing of tables in DB
  @tables = {}
  @config.db = db_name
  WIKK::SQL::each_hash(@config, "show tables") do |row|
    @tables[row["Tables_in_#{db_name}"]] = []
  end

  partition_query = <<-EOF
    select  concat(
            ' --where="'
            ,   concat(
                            coalesce(
                                concat(
                                    p2.partition_expression
                                ,   ' >= '
                                ,   p1.partition_description
                                ,   ' and '
                                )
                            ,   ''
                            )
                        ,   concat(
                                p2.partition_expression
                            ,   ' < '
                            ,   p2.partition_description
                            )
                        ),
            '"'
            ) as where_clause
        ,   p2.table_schema as database_name
        ,   p2.table_name
        ,  concat(
            p2.table_schema, '.', p2.table_name
            ,   '.', p2.partition_name, '.sql'
            ) as output_filename
    from        information_schema.partitions       p1
    right join  information_schema.partitions       p2
    on          p1.table_name                   = p2.table_name
    and         p1.table_schema                 = p2.table_schema 
    and         p1.partition_ordinal_position + 1 = p2.partition_ordinal_position
    where       p2.table_schema = '#{db_name}'
    and         p2.partition_method = 'RANGE COLUMNS'
    order by output_filename
EOF

  #tables with partitions are dumped by partition
  WIKK::SQL::each_hash(@config, partition_query) do |row|
    @tables[row['table_name']] << [row['where_clause'].gsub('`',''), row['output_filename'] ]
  end
end

#Dump each partitioned table as a separate file (keeps locking to a minimum, and easier to restore if the tables are large).
def dump_partitioned_tables(db_name:)
  @tables.each do |table, partitions|
    partitions.each do |partition| 
      command_with_echo "/usr/bin/mysqldump -h #{@config.host} -u #{@config.dbuser} -p#{@config.key} --opt --no-create-info --single-transaction #{partition[0]} #{db_name} #{table} | gzip > #{partition[1]}.gz"
    end
  end
end


#Dump each table (that is not partitioned) as a separate file.
def dump_non_partitioned_tables(db_name:)
  #Do a full dump of the tables which aren't partitioned.
  @tables.each do |table, partitions|
    if partitions.length == 0  #i.e. is a table that isn't partitioned.
     command_with_echo "/usr/bin/mysqldump -h #{@config.host} -u #{@config.dbuser} -p#{@config.key} --opt --no-create-info --single-transaction #{db_name} #{table} | gzip > #{db_name}.#{table}.sql.gz"
    end
  end
end

#Main
load_config
discover_databases
#For each database we want to backup (could get this with a mysql command, but wanted to be more selective).
@databases.each do |db_name|
  puts db_name
  discover_tables(db_name: db_name)
  mk_backup_directory(db_name: db_name)
  save_schema(db_name: db_name)
  dump_non_partitioned_tables(db_name: db_name)
  dump_partitioned_tables(db_name: db_name)
end
