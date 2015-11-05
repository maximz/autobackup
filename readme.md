# Simple, automated backups to local and cloud storage from Linux servers

## Overview

This is a modification of Nick Masluk's excellent Linux backup script at http://www.randombytes.org/backups.html (first script on that page).

I use it to backup mysql, certain directories, and the installed package list on my server. You can modify it to backup anything you'd like.

Changes and additions I made to Nick Masluk's script:

* Prior to the backup, we run a separate script to dump all of mysql and installed packages (follow instructions at http://askubuntu.com/questions/9135/how-to-backup-settings-and-list-of-installed-packages to restore from the dump of installed packages)
* Rather than only being able to backup one directory, we now pass in a list of paths to backup, and we back them up recursively (i.e. we include all subdirectories)
* We tar-gzip the latest backup
* Then we upload that tar to Azure, with MD5 checksum validation for the upload
* By default we store the last 5 days of backups, instead of 31 days. This means that at any time, you'll have the last 5 snapshots available on disk to restore any files in case of errors. The tars, however, are cleared out as soon as they are uploaded. There is no expiration policy for the tars in Azure.
* We relax the .identity file requirements from Nick's original script. I wasn't keen on putting these files in all the paths I wanted to backup, so I ditched this requirement. (Since this was a quick-and-dirty hack, the original .identity-checking code from Nick's script remains; see that note in the installation requirements)

Otherwise, the mechanics are the same as in Nick's original script -- read the introduction at http://www.randombytes.org/backups.html for more.

## Installation

Clone this repo into some folder, e.g. autobackup.
Then create the necessary directories and files:

```
cd autobackup
echo 'placeholder file' > .identity

nano $HOME"/paths_to_backup.txt" # put backup paths here, as explained below

mkdir $HOME"/files_backup/"
echo 'placeholder file -- where the snapshots live' > $HOME"/files_backup/.identity"
mkdir $HOME"/files_backup_tars/"
mkdir $HOME"/logs"
mkdir $HOME"/sql_backup"
```

You can modify the locations of these files at the top of autobackup.sh.

`paths_to_backup.txt` is formatted as follows: each line contains the absolute path of a directory you want to backup recursively, optionally followed by a semicolon and a comment that will remind you why you're backing up that path.

For example, here is an excerpt of my `paths_to_backup.txt`:

```
/home/maxim;my files and backups
/home/shannon;other user files
/etc/apache2;apache config
/var/www;web root
```

Now, let's configure the MySQL backups. Open a MySQL shell and create a read-only backup user:

```
grant select, lock tables on *.* to 'backupuser'@'localhost' identified by 'password';
flush privileges;
```

Now, we need to put the backup user's authentication information, as well as Azure storage information, in our environment variables. Edit your `~/.bash_profile` (or similar) as follows:

```
export MYSQL_BACKUP_PASSWORD="the password you set above"
export AZURE_STORAGE_ACCOUNT=account
export AZURE_STORAGE_ACCESS_KEY='storage access key'
```

We need to make these environment variables available when we run the script through sudo. This means we must also run `sudo visudo` and include this line:

```
Defaults env_keep += "MYSQL_BACKUP_PASSWORD AZURE_STORAGE_ACCOUNT AZURE_STORAGE_ACCESS_KEY"
```

(Alternatively, you can run the script using `sudo -E autobackup.sh`, which acts as a one-off run that includes our environment variables.)

Change your desired container name in azureUpload.py as needed.

Finally, install the Python requirements:

```
sudo apt-get update && sudo apt-get install -y python python-dev python-pip python-virtualenv; # if you don't have python and pip yet
sudo pip install python-dateutil;
sudo pip install azure;
```

We're ready to launch the backup.

## Running

To run manually:

```
sudo ./autobackup.sh
```

View logs at $HOME/logs or in stdout.

To run automatically at every midniht: run `crontab -e` and add the line:

```
@daily . ~/.bash_profile; cd ~/autobackup; sudo ./autobackup.sh
```

Monitor logs for errors -- especially upload errors, in which case the tar directory will continue holding tars that have not yet been uploaded.


## Open issues

Uploading fails for tars over 64MB (which is when chunked uploads kick in) if we enable MD5 hash validation upon upload. See the issue I filed over at the Azure SDK Python repo: https://github.com/Azure/azure-sdk-for-python/issues/264. For now, MD5 hash validation upon upload is disabled to avoid the issue.
