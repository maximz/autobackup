#!/bin/bash

# Dumps MySQL databases and package listing
# @author: Maxim Zaslavsky

# create a read-only mysql user for backups like such:
# grant select, lock tables on *.* to 'backupuser'@'localhost' identified by 'password';
# then run: FLUSH PRIVILEGES
# some links online suggest we might actually need more privileges. use this if so:
#GRANT SELECT , 
#RELOAD , 
#FILE , 
#SUPER , 
#LOCK TABLES , 
#SHOW VIEW ON * . * TO  'dbbackup'@'localhost' IDENTIFIED BY  '***' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;


DUMP_PATH=$HOME"/sql_backup"
MYSQL_BACKUP_USER="backupuser"
# use environment variable for password

rm $DUMP_PATH/*

# MySQL databases
sudo mysqldump --all-databases --flush-privileges --force --user=$MYSQL_BACKUP_USER --password=$MYSQL_BACKUP_PASSWORD > $DUMP_PATH/sqlbackup.sql


# package listing ( see http://askubuntu.com/questions/9135/how-to-backup-settings-and-list-of-installed-packages )

dpkg --get-selections > $DUMP_PATH/Package.list
dpkg -l > $DUMP_PATH/Package.list2 # redundant, but has more version info just in case
sudo cp -R /etc/apt/sources.list* $DUMP_PATH/
sudo apt-key exportall > $DUMP_PATH/Repo.keys