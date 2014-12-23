#!/bin/bash

# Autobackup script

# Verison info:

# Nick Masluk
# 2011-03-29
# 2014-04-21 added check to find_removed() so that it does not run on first
#            backup
# from http://www.randombytes.org/backups.html

# Maxim Zaslavsky edits 12/22/2014
# at https://github.com/maximz/autobackup




# make sql dump into a specific path that's included in backup
echo "preparing for backup ... dumping mysql and installed packages"
./dump_sql_and_packages.sh


# Note:  FILES_PATH and BACKUP_FILES_PATH must both contain a file with filename .identity for this script to run
# FILES_PATH=$HOME"/files/"
FILES_PATH=`pwd`; # using this as a placeholder; put an .identity here
FILES_PATH_LIST=$HOME"/paths_to_backup.txt"
BACKUP_FILES_PATH=$HOME"/files_backup/"
BACKUP_TARS=$HOME/"files_backup_tars/"
SNAPSHOTS_KEEP="5" # set to 0 to disable deleting old snapshots
EXCLUDE="lost+found .identity files_backup files_backup_tars .backup_files_running"
LOG_FILE=$HOME"/logs/backup_files_log_"`date +%F`".txt"
KEEP_LOG="1" # set to 0 to disable, 1 to keep a running log, 2 to delete the log and record only current session
LOCK_FILE=$HOME"/.backup_files_running"

# Check if a backup is already running.  If not, create file $LOCK_FILE to
# indicate to other instances of this script that a backup is running.
if [ ! -e $LOCK_FILE ]; then
  touch $LOCK_FILE
else
  echo "Backup is already running"
  # exit with error code 2 if a backup is already running
  exit 2
fi

# check that .identity exists on the root of the files and backup directories
check_identity() {
  if [ ! -e $FILES_PATH/.identity ] || [ ! -e $BACKUP_FILES_PATH/.identity ]; then
    date +%F\ %T\ %A | $LOG_CMD

    echo "" | $LOG_CMD
    if [ ! -e $FILES_PATH/.identity ]; then
      echo $FILES_PATH "is missing .identity file" | $LOG_CMD
    fi
    if [ ! -e $BACKUP_FILES_PATH/.identity ]; then
      echo $BACKUP_FILES_PATH "is missing .identity file" | $LOG_CMD
    fi

    # remove $LOCK_FILE to indicate the script is done running
    rm -f $LOCK_FILE
    echo "" | $LOG_CMD
    echo "--------------------------------------------------------------------------------" | $LOG_CMD
    exit 3
  fi
}

set_dirs() {
  date +%F\ %T\ %A | $LOG_CMD
  echo "" | $LOG_CMD

  # directory where last complete backup is located
  LAST_BACKUP_DIR=`ls $BACKUP_FILES_PATH | sort | grep ^"....-..-.._..\...\..."$ | tail -1`
# for some reason -n never returned false when the string was ""
#  if [ -n $LAST_BACKUP_DIR ]; then
  if [[ $LAST_BACKUP_DIR != "" ]]; then
    echo "Last completed backup is located in" $LAST_BACKUP_DIR | $LOG_CMD
  else
    echo "No previous backup found, all files will be newly copied" | $LOG_CMD
  fi
  # directory where this finalized backup will reside
  CURRENT_BACKUP_DIR=`date +%F_%H.%M.%S`
  echo "This backup will reside in" $CURRENT_BACKUP_DIR "if completed" | $LOG_CMD

  # check if incomplete backups exist
  if [[ `ls $BACKUP_FILES_PATH | sort | grep ^"tmp\.....-..-.._..\...\..."$ | wc -l` -eq 0 ]]; then
    # temporary location for backup while backup is running
    TEMP_BACKUP_DIR=tmp.`date +%F_%H.%M.%S`
    mkdir $BACKUP_FILES_PATH/$TEMP_BACKUP_DIR
  else
    if [[ `ls $BACKUP_FILES_PATH | sort | grep ^"tmp\.....-..-.._..\...\..."$ | wc -l` -gt 1 ]]; then
      echo "More than one partial backup exists, cancelling backup" | $LOG_CMD
      # if more than one partial backup exists, terminate backup
      # remove $LOCK_FILE to indicate the script is done running
      rm -f $LOCK_FILE
      echo "" | $LOG_CMD
      echo "--------------------------------------------------------------------------------" | $LOG_CMD
      exit 4
    else
      # set temporary backup location to that of the partially completed backup
      TEMP_BACKUP_DIR=`ls $BACKUP_FILES_PATH | sort | grep tmp.`
      echo "A partial backup exists in" $TEMP_BACKUP_DIR "and will resume now" | $LOG_CMD
    fi
  fi
}

run_backup() {
  # generate a list of items to ignore
  EXCLUDED=""
  for i in $EXCLUDE; do
    EXCLUDED="$EXCLUDED --exclude=$i";
  done

  ID_FILES=`cat $FILES_PATH/.identity`
  ID_BACKUP_FILES=`cat $BACKUP_FILES_PATH/.identity`
  echo "" | $LOG_CMD
  echo "Starting rsync backup, from" $ID_FILES "to" $ID_BACKUP_FILES | $LOG_CMD
  #rsync $EXCLUDED --delete-after -av --link-dest=$BACKUP_FILES_PATH/$LAST_BACKUP_DIR/ $FILES_PATH $BACKUP_FILES_PATH/$TEMP_BACKUP_DIR/ 2>&1 | $LOG_CMD
  
 ERROR=0
 while read line; do
    # each line is now stored in $line
    echo "backing up:" "$line"
    # each line is in format: filepath;some comment for us
    # so we need to split the line by ;, so use http://stackoverflow.com/a/5257398/130164
    arrIn=(${line//;/ })
    rsync $EXCLUDED --delete-after -arv --relative --link-dest="$BACKUP_FILES_PATH/$LAST_BACKUP_DIR/" "${arrIn[0]}" "$BACKUP_FILES_PATH/$TEMP_BACKUP_DIR/" 2>&1 | $LOG_CMD
  # store error code from rsync's exit
  ERROR=$((ERROR+${PIPESTATUS[0]}))
  echo "errorcnt" "$ERROR"
  done < "$FILES_PATH_LIST"
  # if rsync succeeds, move the temporary backup location to its final location
  if [ $ERROR == 0 ]; then
    mv "$BACKUP_FILES_PATH/$TEMP_BACKUP_DIR" "$BACKUP_FILES_PATH/$CURRENT_BACKUP_DIR"
    # tar up
    tar -zcvf $BACKUP_TARS/${CURRENT_BACKUP_DIR}.tar.gz $BACKUP_FILES_PATH/$CURRENT_BACKUP_DIR
  fi
  
}

find_removed() {
  # don't look for removed files if this is the first backup
  if [[ $LAST_BACKUP_DIR != "" ]]; then
    echo "" | $LOG_CMD
    echo "Files removed since last backup:" | $LOG_CMD
    # run a dry rsync run between current and previous backups to determing which files were removed
    rsync $EXCLUDED --delete-before -avn $BACKUP_FILES_PATH/$CURRENT_BACKUP_DIR/ $BACKUP_FILES_PATH/$LAST_BACKUP_DIR/ | grep ^"deleting " | cut --complement -b 1-9 | $LOG_CMD
  fi
}

del_old_snapshots() {
  if [ $SNAPSHOTS_KEEP -gt 0 ]; then # disable deleting snapshots if SNAPSHOTS=0
    NUMBER_SHOTS=`ls $BACKUP_FILES_PATH | sort | grep -v lost+found | wc -l`
    NUMBER_DEL=0
    if [ $NUMBER_SHOTS -gt $SNAPSHOTS_KEEP ]; then
      NUMBER_DEL=$(($NUMBER_SHOTS - $SNAPSHOTS_KEEP))
      echo ""| $LOG_CMD
      echo "Removing" $NUMBER_DEL "old backups" | $LOG_CMD
    fi
    for OLD_DIR in $(ls $BACKUP_FILES_PATH | sort | grep -v lost+found | head -$NUMBER_DEL) ; do
      echo "Removing" $BACKUP_FILES_PATH/$OLD_DIR | $LOG_CMD
      rm -rf $BACKUP_FILES_PATH/$OLD_DIR
    done
  fi
}

if [ $KEEP_LOG -eq 1 ] || [ $KEEP_LOG -eq 2 ]; then
  # run backup logged
  if [ $KEEP_LOG -eq 2 ] && [ -e $LOG_FILE ]; then
    # if log mode is set to "2", delete old log file before starting (if it exists)
    rm -f $LOG_FILE
  fi
  # set log command to split stdout into a log file and stdout
  LOG_CMD="tee -a $LOG_FILE"
else
  # set log command to only print to stdout
  LOG_CMD="cat"
fi

# check that .identity files exist in files and backup directories
check_identity
# set directory locations of backup
set_dirs
# run rsync backup
run_backup
# find files which have been removed since last backup
find_removed
# remove old snapshots
del_old_snapshots
# remove $LOCK_FILE to indicate the script is done running
rm -f $LOCK_FILE

echo "uploading to azure" | $LOG_CMD
# now upload to azure the contents of the backup_tars dir
# find the tar.gz's and pipe their full paths into our python script
ls -d $BACKUP_TARS/* | grep .tar.gz | python azureUpload.py | $LOG_CMD

ERROR2=${PIPESTATUS[0]}

# now clear that dir
if [ $ERROR2 -eq 0 ]; then
echo "clearing tar directory" | $LOG_CMD
rm $BACKUP_TARS/*.tar.gz
else
echo "upload failed; not clearing tar directory"
fi



echo "" | $LOG_CMD
echo "exit code" "$ERROR"
date +%F\ %T\ %A | $LOG_CMD
echo "--------------------------------------------------------------------------------" | $LOG_CMD
# exit with the error code left by rsync
exit $ERROR



