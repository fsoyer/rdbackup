# rdbackup backup script (RDIFF-BACKUP over SSH and RSYNC)
(c) Frank Soyer <frank.soyer@gmail.com> 2010
http://wiki.kogite.fr/index.php/Rdiff-backup

freely based on sbackup.sh (RSYNC)

Changelog :
* 3.4 - Move some global variables from .conf to .sh. Variable can be overwritten if added (uncommented) in the .conf file
* 3.3.6 - Suppress "grep -v postgre" from pg_dump to backup Postre system db
* 3.3.5 - Added rollback on backup directory with --check-destination if backup fails
* 3.3.4 - Added a variable for mail executable program to enable alternatives (mailx, nail, ...)
* 3.3.3 - Begin with wakeonlan and ping test loop to stop script if host is unreachable
   * - Added --print-statistics to rdiff options in conf.sample
* 3.3.2 - Added mysqlcheck before mysqldump
* 3.3.1 - moving pre-script execution at the beginning of the main loop (exit if it fails w/ going further)
* 3.3 - Stable (merge experiment -> master, 3.2.2 -> 3.3)
* 3.2.2 - dumps already kept one week wirth day number : no need to rename the .gz in .gz.0
    * Corrected dome typo, added some comments in backup log file
* 3.2.1 - Use SUFFIX in dump file names mysql and pgsql 
    * - Add returned error test to dumps 
* 3.2 - Add SSHCMD fot remote dump if SLOCAL=1
* 3.1 - Add LDAP backup
    * - Wakeonlan if backup server is down
* 3.0 - Return to a normal usage of "--include" from rdiff-backup instead of backuping each dir. individually. This allow tools like rdiff-backup-web to handle entire backup of a server. 
* 2.6 - some optimizations on directional options
* 2.5 - Ehance directional options (local/remote choice for source OR destination)
* 2.4 - Stop if necessary Apache service before dumping MySQL
* 2.3 - Add backup sens (local to local or local to remote)
    * - Add backup destination in .conf file : LOCAL or REMOTE
* 2.2 - Reverse backup from client to backup server
* 2.1 - Add handle for a pre-backup script (if pre-backup script ended with error <> 0, main script stops)
* 2.0 - Moving variables in a .conf file

# Dependencies :
mailx rdiff-backup rsync

# Instructions
Create two files for include and excludes files :

* rdbackup_SERVERNAME.list (see LIST parameter in .conf file)
* rdbackup_SERVERNAME.exclude (see EXCLUDE parameter in .conf file)

These files needs to contain list of **Directory**

Add this to your crontab :

    # m h  dom mon dow   command
    30 12 * * * /home/USER/.rdbackup/rdbackup.sh /home/USER/.rdbackup/rdbackup.conf

# WakeOnLan (Debian)
You need to install ethtool :
 aptitude install ethtool
Add this in /etc/network/interfaces :
 iface eth0 inet dhcp
	ethernet-wol g

# Ldap dump
You need to install ldap utils
 aptitude install ldap-utils
