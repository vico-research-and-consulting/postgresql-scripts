#!/bin/bash

DUMPDIR="$1"
BACKUPDIR="$1"
MAXAGE="$2"

TIMESTAMP="`date --date="today" "+%Y-%m-%d_%H-%M-%S"`"
STARTTIME_GLOBAL="$SECONDS"
BACKUP_TYPE="${BACKUP_TYPE:-custom}"

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
	echo "       $0 <DUMP PATH>:<BACKUP PATH> <MAXAGE IN DAYS>"
	exit 1
fi

if [ "$(whoami)" != "postgres" ];then
  echo "INFO: not postgres, executing myself with sudo now"
  exec sudo -u postgres $0 $@
fi

echo "INFO: adjusting /proc/$$/oom_score_adj to 1000"
echo 1000 > /proc/$$/oom_score_adj

if ( echo "$BACKUPDIR"|grep -q -P "/....+:/....+");then
	DUMPDIR="$(echo "$BACKUPDIR"|cut -d ':' -f1)"
	BACKUPDIR="$(echo "$BACKUPDIR"|cut -d ':' -f2)"
  echo "INFO: a dumpdir was specified: $DUMPDIR"
fi

if [ ! -d "$BACKUPDIR" ];then
    mkdir -p "$BACKUPDIR"
fi

if [ ! -d "$DUMPDIR" ];then
    mkdir -p "$DUMPDIR"
fi

cd ${BACKUPDIR} 
if [ "$?" != 0 ];then
   echo "Unable to change to dir '${BACKUPDIR}'"
	exit 1 
fi

if ( ! ( echo "$BACKUP_TYPE" |grep -q -P "custom|sql" ) );then
   echo "Wrong backup type '$BACKUP_TYPE', use 'cusom' or 'sql'"
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

   echo "=> backup schema"
   pg_dump -c $DBNAME -s -f ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_schema.sql.gz -Z 7
   RET1="$?"

   echo "=> backup database"

   if [ "$BACKUP_TYPE" = "custom" ];then
      pg_dump -Fc -c -f ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_currently_dumping.custom.gz -Z 7 --inserts $DBNAME && 
         mv ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_currently_dumping.custom.gz ${DUMPDIR}/${DBNAME}-${TIMESTAMP}.custom.gz
      RET2="$?"
   else
      pg_dump -f ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_currently_dumping.sql.gz -Z 7 $DBNAME && 
         mv ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_currently_dumping.sql.gz ${DUMPDIR}/${DBNAME}-${TIMESTAMP}.sql.gz
      RET2="$?"
   fi

   if [ "${DUMPDIR}" != "${BACKUPDIR}" ];then
      echo "=> move backups to ${BACKUPDIR}"
		mv -v ${DUMPDIR}/${DBNAME}-${TIMESTAMP}_schema.sql.gz ${BACKUPDIR}/${DBNAME}-${TIMESTAMP}_schema.sql.gz &&
      if [ "$BACKUP_TYPE" = "custom" ];then
         mv -v ${DUMPDIR}/${DBNAME}-${TIMESTAMP}.custom.gz ${BACKUPDIR}/${DBNAME}-${TIMESTAMP}.custom.gz
      else
         mv -v ${DUMPDIR}/${DBNAME}-${TIMESTAMP}.sql.gz ${BACKUPDIR}/${DBNAME}-${TIMESTAMP}.sql.gz
      fi
      RET3="$?"
   else
	  RET3="0"
   fi

   DURATION="$(( $(( $SECONDS - $STARTTIME )) / 60 ))"
   if ( [ "$RET1" == "0" ] && [ "$RET2" == "0" ] && [ "$RET3" == "0" ]);then
        sendStatus "INFO: SUCESSFULLY CREATED BACKUP FOR '$DBNAME' after $DURATION minutes"
        SUCCESSFUL="$(( $SUCCESSFUL + 1))"
   else
     FAILED="$(($FAILED + 1))"
        sendStatus "ERROR: FAILED TO BACKUP '$DBNAME' after $DURATION minutes"
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
	find ${BACKUPDIR} -type f -name "*.custom.gz" -mtime +${MAXAGE} -exec rm -fv {} \;
	find ${BACKUPDIR} -type f -name "*.sql.gz" -mtime +${MAXAGE} -exec rm -fv {} \;
else
	echo "Age not correctly defined, '$MAXAGE'"
	exit 1 
fi

echo "TOTAL AMOUNT OF BACKUPS $( du -scmh *.custom.gz|awk '/total/{print $1}')"
