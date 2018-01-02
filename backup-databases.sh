#!/bin/bash

BACKUPDIR="$1"
MAXAGE="$2"

TIMESTAMP="`date --date="today" "+%Y-%m-%d_%H-%M-%S"`"
STARTTIME_GLOBAL="$SECONDS"

sendStatus(){
    local STATUS="$1"
    echo ">>>>$STATUS<<<<"
    logger -t "backup-databases.sh" "$STATUS"
    if (which zabbix_sender &>/dev/null);then
      zabbix_sender -s `hostname` -c /etc/zabbix/zabbix_agentd.conf -k postgresql.backup.globalstatus -o "$STATUS" > /dev/null
    fi
}


if [ -z "$BACKUPDIR" ] || [ -z "$MAXAGE" ];then
	echo "USAGE: $0 <BACKUP PATH> <MAXAGE IN DAYS>"
	exit 1
fi

cd $BACKUPDIR 
if [ "$?" != 0 ];then
        echo "Unable to change to dir '$BACKUPDIR'"
	exit 1 
fi

LOCK_FILE="/tmp/postgresql-backup.lock"
if ( ! ( set -C; : > $LOCK_FILE 2> /dev/null ) );then
  echo "Already running"
  exit 1
fi
trap "rm -f $LOCK_FILE; echo removed $LOCK_FILE" EXIT TERM INT

sendStatus "INFO: STARTING DATABASE BACKUP"

FAILED="0"
SUCCESSFUL="0"

while read DBNAME;
do
   echo "*** BACKUP $DBNAME ****************************************************************************"
   STARTTIME="$SECONDS"
   pg_dump $DBNAME |
	    gzip -c > ${DBNAME}-${TIMESTAMP}_currently_dumping.sql.gz && 
	 mv ${DBNAME}-${TIMESTAMP}_currently_dumping.sql.gz ${DBNAME}-${TIMESTAMP}.sql.gz
   RET="$?"

   DURATION="$(( $(( $SECONDS - $STARTTIME )) / 60 ))"
   if [ "$RET" == "0" ];then
        sendStatus "INFO: SUCESSFULLY CREATED BACKUP FOR '$DBNAME' in $DURATION minutes"
        SUCCESSFUL="$(( $SUCCESSFUL + 1))"
   else
     FAILED="$(($FAILED + 1))"
        sendStatus "INFO: FAILED TO BACKUP '$DBNAME'  in $DURATION minutes"
   fi
done < <(psql -q -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;")

DURATION="$(( $(( $SECONDS - $STARTTIME_GLOBAL )) / 60 ))"
if [ "$FAILED" -gt 0 ];then 
  sendStatus "ERROR: FAILED ($FAILED failed backups,  $SUCCESSFUL successful backup ($DURATION minutes)"
else
  sendStatus "OK: $SUCCESSFUL BACKUPS WERE SUCCESSFUL ($DURATION minutes)"
fi

echo "*** REMOVE OUTDATED BACKUPS **********************************************************************"

if ( echo -n "$MAXAGE"|egrep -q '^[0-9][0-9]*$' );then
	find $BACKUPDIR -name "*.sql.gz" -mtime +${MAXAGE} -exec rm -fv {} \;
else
	echo "Age not correctly defined"
	exit 1 
fi

echo "TOTAL AMOUNT OF BACKUPS $( du -scmh *.sql.gz|awk '/total/{print $1}')"
