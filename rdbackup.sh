#!/bin/bash
# Backup Script (RDIFF-BACKUP over SSH and RSYNC)
# v3.5
# See README.md for details
# (c) 2005, Frank Soyer <frank.soyer@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# The GNU General Public License is available at:
# http://www.gnu.org/copyleft/gpl.html

ERROR_FLAG=0
ERROR=0
ERRORS="ERREURS: "

ELAPSED=$(which time)
if [ ! -x $ELAPSED ]
then
   unset ELAPSED
else
   ELAPSED="$ELAPSED -fElapsed:%E"
fi

# Initialize global variables (can be overwritten in .conf file)
# --------------------------------------
# Mail program (mail, mailx, nail...)
# --------------------------------------
MAILBIN="/usr/bin/mail -s"
# --------------------------------------
# Rdiff-backup options 
# --------------------------------------
RDIFF_OPTS="-v4 --force --create-full-path --exclude-fifos --exclude-sockets --print-statistics"
RETENTION=1W
# --------------------------------------
# Databases options 
# --------------------------------------
MYSQLDUMP_OPTS="--routines"
PGSQLDUMP_OPTS=""
STOPSEAFILE=0
SOGOBACKUP=0

# --------------------------------------
# Load variables from config file
# --------------------------------------
if [ $# -gt 0 ]
then
# let use the given full path config (.conf) file
   if [ -f $1 ]
   then
      . $1
   else
      echo "$1 introuvable !"
	  rm -f $APPLICATION_DIR/$PID_FILE
      exit 1
   fi
else
   if [ -f $(dirname $0)/rdbackup.conf ]
   then
      . $(dirname $0)/rdbackup.conf
   else
      echo "$(dirname $0)/rdbackup.conf introuvable !"
	  rm -f $APPLICATION_DIR/$PID_FILE
      exit 1
   fi
fi

# How many backups to keep
if [ $JUSTLAST -eq 0 ]
then
   JOUR=$(date +%w)
else
   JOUR=0
fi
# --------------------------------------
# Databases list 
# Can't be initialized before including .conf file because we need databases PASSWORDs
# --------------------------------------
if [ ! "$MYDB" ]
then
   # Find which databases to dump, each in an individual dump file
   MYDB="mysql --execute 'show databases\G' --password=$MYSQL_PASSWORD | grep -v row | sed -e 's/Database: //g' | grep -v mysql | grep -v information_schema | grep -v performance_schema"
fi
if [ ! "$PGDB" ]
then
   # Find which databases to dump, each in an individual dump file
   PGDB="su - postgres -c 'psql -l --pset tuples_only' | awk '{print \$1}' | grep -v ^$ | grep -v template | grep -v : | grep -v '|'"
fi

if [ ! -e $SCRIPT_DIR/$PID_FILE ]
then
   if [ $SLOCAL -eq 0 -a $DLOCAL -eq 0 ]
   then
      echo "La source ET la destination ne peuvent pas être toutes deux externes."
      echo "Au moins une des deux (ou les deux) doi(ven)t être local(es)."
      echo "Vérifier les valeurs de SLOCAL et DLOCAL"
	  rm -f $APPLICATION_DIR/$PID_FILE
      exit 1
   fi

   if [ ! -z "$LIST" ]
   then
      if [ ! -f $LIST ]
      then
         echo "$LIST introuvable !"
		 rm -f $APPLICATION_DIR/$PID_FILE
         exit 1
      fi
      while read line
      do
         if [ ! -z "$line" ]
         then
            if [ -z "$INCLUDE_OPT" ]
            then
               INCLUDE_OPT="--include $line"
            else
               INCLUDE_OPT="$INCLUDE_OPT --include $line"
            fi
         fi
         shift
      done < $LIST
      # Add a final exclusion of "/" to avoid full root backup
      INCLUDE_OPT="$INCLUDE_OPT --exclude '**'"
   fi

   if [ ! -z "$EXCLUDE" ]
   then
      if [ ! -f $EXCLUDE ]
      then
         echo "$EXCLUDE introuvable !"
		 rm -f $APPLICATION_DIR/$PID_FILE
         exit 1
      fi
      EXCLUDE_OPT=""
      while read line
      do
         if [ ! -z "$line" ]
         then
            if [ -z "$EXCLUDE_OPT" ]
            then
               EXCLUDE_OPT="--exclude $line"
            else
               EXCLUDE_OPT="$EXCLUDE_OPT --exclude $line"
           fi
         fi
         shift
      done < $EXCLUDE
   fi

   if [ -e  $SCRIPT_DIR/$LOG_FILE ]
   then
        mv $SCRIPT_DIR/$LOG_FILE $SCRIPT_DIR/$LOG_FILE.0
   fi
   date > $SCRIPT_DIR/$LOG_FILE
   echo >> $SCRIPT_DIR/$LOG_FILE

## Wakeonlan and alive test : test and/or wake up the server
   if [ $SLOCAL -eq 0 -o $DLOCAL -eq 0 ]
   then
      STARTTIME=$(date +%s)
      ELAPSEDTIME=0
      ping -c 1 $REMOTEIP >> $SCRIPT_DIR/$LOG_FILE 2>&1
      # If server is unreachable, try for one hour
      while [ $? -ne 0 -a $ELAPSEDTIME -lt 3600 ]
      do
         if [ $WAKEONLAN -eq 1 ]
         then
            WAKEONLANBIN=$(which wakeonlan)
            if [ $WAKEONLANBIN ]
            then
               $WAKEONLANBIN $MAC 2>> $SCRIPT_DIR/$LOG_FILE
               sleep 60
               ping -c 1 $REMOTEIP
               if [ $? -ne 0 ]
               then
                  echo "$REMOTEIP injoignable !" >> $SCRIPT_DIR/$LOG_FILE 2>&1
				  rm -f $APPLICATION_DIR/$PID_FILE
                  exit 1
               fi
            else
               echo "Programme WAKEONLAN introuvable !" >> $SCRIPT_DIR/$LOG_FILE 2>&1
               exit 1
            fi
         fi
         ELAPSEDTIME=$(($(date +%s)-STARTTIME))
         ping -c 1 $REMOTEIP >> /dev/null 2>&1
      done
      if [ $? -ne 0 ]
      then
         rm -f $SCRIPT_DIR/$PID_FILE
         (echo "$SERVERNAME IS UNREACHABLE") | $MAILBIN "rdbackup : ACCESS ERROR ON $SERVERNAME [on $(hostname)] $(date +%d/%m)" $MAIL_ADMIN
		 rm -f $APPLICATION_DIR/$PID_FILE
         exit 1
      fi
   fi

## Script pre-backup
   if [ ! -z $PRESCRIPT ]
   then
      . $PRESCRIPT
      if [ $? -ne 0 ]
      then
         rm -f $SCRIPT_DIR/$PID_FILE
         (echo "$PRESCRIPT ERROR ON $HOSTNAME") | $MAILBIN "rdbackup : BACKUP ERROR ON $SERVERNAME [on $(hostname)] $(date +%d/%m)" $MAIL_ADMIN
         rm -f $APPLICATION_DIR/$PID_FILE
		 exit 1
      fi
   fi

   echo $$ > $SCRIPT_DIR/$PID_FILE

   if [ ! -d $BCK_DIR -a $DLOCAL -eq 1 ]
   then
      mkdir -p $BCK_DIR
      if [ $? -ne 0 ]
      then
         echo "Creation $BCK_DIR impossible !"
		 rm -f $APPLICATION_DIR/$PID_FILE
         exit 1
      fi
   fi
   if [ $SLOCAL -eq 0 ]
   then
      RSSCHEMA=--remote-schema
      RSOPTION="\"ssh -p $REMOTEPORT %s rdiff-backup --server\""
      SDIR="$REMOTEUSR@$REMOTEIP::/"
      SSHCMD="ssh -p $REMOTEPORT $REMOTEIP "
   else
      RSSCHEMA=""
      RSOPTION=""
      SDIR="/"
      SSHCMD=""
   fi
   if [ $DLOCAL -eq 0 ]
   then
      RDSCHEMA=--remote-schema
      RDOPTION="\"ssh -p $REMOTEPORT %s rdiff-backup --server\""
      DDIR="$REMOTEUSR@$REMOTEIP::${BCK_DIR}"
   else
      RDSCHEMA=""
      RDOPTION=""
      DDIR="${BCK_DIR}"
   fi

   if [ $STOPAPACHE -eq 1 ]
   then
      echo "Stopping Apache" >> $SCRIPT_DIR/$LOG_FILE
      $SSHCMD "systemctl stop httpd"
   fi

   if [ $STOPSEAFILE -eq 1 ]
   then
      echo "Stopping Seafile" >> $SCRIPT_DIR/$LOG_FILE
      $SSHCMD "systemctl stop seahub"
      $SSHCMD "systemctl stop seafile"
   fi

## Mysql dump
   if [ $MYSQLDUMP -eq 1 -a ! "$MYDB" == "" ]
   then
      $SSHCMD "ls $DUMP_DIR" >/dev/null 2>&1
      if [ $? -ne 0 ]
      then
         echo "Creating $DUMP_DIR" >> $SCRIPT_DIR/$LOG_FILE
         $SSHCMD " mkdir -p $DUMP_DIR" >> $SCRIPT_DIR/$LOG_FILE 2>&1
      fi
      echo "MySQL dump " $(date) >> $SCRIPT_DIR/$LOG_FILE
      echo "$SSHCMD $MYDB" >> $SCRIPT_DIR/$LOG_FILE
      MYDBLIST=$($SSHCMD $MYDB 2>&1)
      if [[ $MYDBLIST =~ "ERROR" ]]
      then
         echo $MYDBLIST >> $SCRIPT_DIR/$LOG_FILE
         ERRORS="$ERRORS MYSQLDUMP=error $MYDBLIST"
         ERROR_FLAG=1
         MYDBLIST=
      fi
      # customize field separator to handle spaces in db names
      oIFS=$IFS
      IFS=$'\n'
      for DB in $MYDBLIST
      do
         IFS=$oIFS # List is OK, reset IFS
         echo "MYSQLCHECK " $DB $(date) >> $SCRIPT_DIR/$LOG_FILE 2>&1
         $SSHCMD "mysqlcheck \"$DB\" --silent --auto-repair --password=$MYSQL_PASSWORD" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         echo "MYSQLDUMP " $DB $(date) >> $SCRIPT_DIR/$LOG_FILE 2>&1
         $SSHCMD "mysqldump \"$DB\" $MYSQLDUMP_OPTS --password=$MYSQL_PASSWORD > $DUMP_DIR/my_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         ERROR=$?
         if [ $ERROR -ne 0 ]
         then
            ERRORS="$ERRORS MYSQLDUMP=error $ERROR:"
            ERROR_FLAG=1
         else
            $SSHCMD "rm -f $DUMP_DIR/my_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql.gz" 2>> $SCRIPT_DIR/$LOG_FILE
            $SSHCMD "gzip $DUMP_DIR/my_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql" 2>> $SCRIPT_DIR/$LOG_FILE
         fi
      done
      IFS=$oIFS # force reset IFS
   fi

## PostgreSQL dump
   if [ $PGSQLDUMP -eq 1 -a ! "$PGDB" == "" ]
   then
      echo "PostgreSQL dump " $(date) >> $SCRIPT_DIR/$LOG_FILE
      PGDBLIST=$($SSHCMD $PGDB) >> $SCRIPT_DIR/$LOG_FILE 2>&1
      # customize field separator to handle spaces in db names
      oIFS=$IFS
      IFS=$'\n'
      for DB in $PGDBLIST
      do
         IFS=$oIFS
         echo "VACUUMDB " $DB $(date) >> $SCRIPT_DIR/$LOG_FILE 2>&1
         $SSHCMD "su - postgres -c \"vacuumdb -U postgres -d $DB -f -q -z\"" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         echo "PG_DUMP " $DB $(date) >> $SCRIPT_DIR/$LOG_FILE 2>&1
         $SSHCMD "su - postgres -c \"pg_dump $PGSQLDUMP_OPTS $DB\" > $DUMP_DIR/pg_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         ERROR=$?
         if [ $ERROR -ne 0 ]
         then
            ERRORS="$ERRORS PGDUMP=error $ERROR:"
            ERROR_FLAG=1
         else
            $SSHCMD "rm -f $DUMP_DIR/pg_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql.gz" 2>> $SCRIPT_DIR/$LOG_FILE
            $SSHCMD "gzip $DUMP_DIR/pg_${SUFFIX}_$(echo $DB|tr ' ' '_')_${JOUR}.sql" 2>> $SCRIPT_DIR/$LOG_FILE
         fi
      done
   fi

   if [ $STOPAPACHE -eq 1 ]
   then
      echo "Starting Apache" >> $SCRIPT_DIR/$LOG_FILE
      $SSHCMD "systemctl start httpd"
   fi

## backup LDAP
   if [ $SLAPCAT -eq 1 ]
   then
      SLAPCATBIN=$($SSHCMD "which slapcat")
      if [ $SLAPCATBIN ]
      then
         echo "LDAP dump " $(date) >> $SCRIPT_DIR/$LOG_FILE
         $SSHCMD "slapcat -c -l $DUMP_DIR/ldap_${SUFFIX}_${JOUR}.ldif" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         ERROR=$?
         if [ $ERROR -ne 0 ]
         then
            ERRORS="$ERRORS SLAPCAT=error $ERROR:"
            ERROR_FLAG=1
         else
            $SSHCMD "rm -f $DUMP_DIR/ldap_${SUFFIX}_${JOUR}.ldif.gz" 2>> $SCRIPT_DIR/$LOG_FILE
            $SSHCMD "gzip $DUMP_DIR/ldap_${SUFFIX}_${JOUR}.ldif" 2>> $SCRIPT_DIR/$LOG_FILE
         fi
      else
         echo "Programme SLAPCAT introuvable !" >> $SCRIPT_DIR/$LOG_FILE 2>&1
      fi
   fi

## backup SOGo
   if [ $SOGOBACKUP -eq 1 ]
   then
      SOGOTOOLBIN=$($SSHCMD "which sogo-tool")
      if [ ! -z "$SOGOTOOLBIN" ]
      then
         $SSHCMD "ls $DUMP_DIR/sogo_backups" >/dev/null 2>&1
         if [ $? -ne 0 ]
         then
            echo "Creating $DUMP_DIR/sogo_backups" >> $SCRIPT_DIR/$LOG_FILE
            $SSHCMD "mkdir -p $DUMP_DIR/sogo_backups" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         fi

         echo "SOGO backup " $(date) >> $SCRIPT_DIR/$LOG_FILE
         $SSHCMD "$SOGOTOOLBIN backup $DUMP_DIR/sogo_backups ALL" >> $SCRIPT_DIR/$LOG_FILE 2>&1
         ERROR=$?
         if [ $ERROR -ne 0 ]
         then
            ERRORS="$ERRORS SOGOBACKUP=error $ERROR:"
            ERROR_FLAG=1
         else
            $SSHCMD "rm -f $DUMP_DIR/sogobackup_${JOUR}.tgz" 2>> $SCRIPT_DIR/$LOG_FILE
            $SSHCMD "tar -cvzf $DUMP_DIR/sogobackup_${JOUR}.tgz $DUMP_DIR/sogo_backups/*" 2>> $SCRIPT_DIR/$LOG_FILE
         fi
      else
         echo "Programme SOGO-TOOL introuvable !" >> $SCRIPT_DIR/$LOG_FILE 2>&1
      fi
   fi

## Boucle de backup
   /usr/bin/logger "Sauvegarde rdiff $SERVERNAME"
   echo >> $SCRIPT_DIR/$LOG_FILE
   echo "Backup $SERVERNAME" $(date) >> $SCRIPT_DIR/$LOG_FILE
   echo rdiff-backup $RDIFF_OPTS $EXCLUDE_OPT $INCLUDE_OPT $RSSCHEMA $RSOPTION $SDIR $DDIR >> $SCRIPT_DIR/$LOG_FILE
# Note : "eval" is necessary to correctly keep the quotes in $RSOPTION
   eval $ELAPSED rdiff-backup $RDIFF_OPTS $EXCLUDE_OPT $INCLUDE_OPT $RSSCHEMA $RSOPTION $SDIR $DDIR >> $SCRIPT_DIR/$LOG_FILE 2>&1
   ERROR=$?
   if [ $ERROR -ne 0 ]
   then
      ERRORS="$ERRORS $BASE=error $ERROR:"
      ERROR_FLAG=1
   else
      if [ "${RETENTION:0:19}" != "--remove-older-than" ]
      then
         RETENTION="--remove-older-than $RETENTION --force"
      fi
      echo "Cleaning backups" $(date) >> $SCRIPT_DIR/$LOG_FILE
      echo rdiff-backup $RDSCHEMA $RDOPTION $RETENTION $DDIR >> $SCRIPT_DIR/$LOG_FILE
# Note : "eval" is necessary to correctly keep the quotes in $RDOPTION
      eval rdiff-backup $RDSCHEMA $RDOPTION $RETENTION $DDIR >> $SCRIPT_DIR/$LOG_FILE 2>&1
      ERROR=$?
      if [ $ERROR -ne 0 ]
      then
         ERRORS="$ERRORS $BASE=$ERROR:"
         ERROR_FLAG=1
      fi
   fi

   if [ $STOPSEAFILE -eq 1 ]
   then
      echo "Starting Seafile" >> $SCRIPT_DIR/$LOG_FILE
      $SSHCMD "systemctl start seafile"
      $SSHCMD "systemctl start seahub"
   fi

   if [ $ERROR_FLAG -eq 1 ]
   then
      (echo $ERRORS
       date
       echo Voir $SCRIPT_DIR/$LOG_FILE
       grep -i warning $SCRIPT_DIR/$LOG_FILE
       grep -i error $SCRIPT_DIR/$LOG_FILE
       grep -i corrupt $SCRIPT_DIR/$LOG_FILE
      )| $MAILBIN "rdbackup : RDIFF ERROR ON $SERVERNAME [on $(hostname)] $(date +%d/%m)" $MAIL_ADMIN
      rdiff-backup -v5 --check-destination-dir $DDIR >> $SCRIPT_DIR/$LOG_FILE 2>&1
   else
     # Script post-backup
      if [ -f $POSTSCRIPT ]
      then
         $POSTSCRIPT
         if [ $? -ne 0 ]
         then
            ERRORS="$ERRORS - Script POST-BACKUP error"
            ERROR_FLAG=1
         fi
      fi
      if [ $MAIL_IF_SUCCESS -eq 1 ]
      then
         if [ $ERROR_FLAG -eq 0 ]
         then
            ERRORS=""
         fi
         (date
          echo $ERRORS
          ls -l $SCRIPT_DIR/$LOG_FILE
         )| $MAILBIN "rdbackup : Backup $SERVERNAME [on $(hostname)] successfull $(date +%d/%m)" $MAIL_ADMIN
      fi
   fi
   date >> $SCRIPT_DIR/$LOG_FILE
   /usr/bin/logger "FIN rdiff $SERVERNAME"
   rm -f $SCRIPT_DIR/$PID_FILE
else
    (echo "$HOSTNAME:$SCRIPT_DIR/$PID_FILE existe : abandon de $0") | $MAILBIN "rdbackup : BACKUP ERROR ON $SERVERNAME [on $(hostname)] $(date +%d/%m)" $MAIL_ADMIN
fi
