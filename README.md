
Activate Backup
===============

Fior systems without automation.

* Clone dir
  ```
  cd /opt
  git clone https://github.com/vico-research-and-consulting/postgresql-scripts.git
  chown postgres:postgres /opt/postgresql-scripts
  ```
* Create backup dir
  ```
  mkdir /srv/postgresql-backup
  chown postgres:postgres /srv/postgresql-backup
  ```
* Activate job
  ```
  echo "0 2 * * * postgres /opt/postgresql-scripts/backup-databases.sh /srv/postgresql-backup 5 2>&1| logger -t postgresql-backup" > /etc/cron.d/postgresql-backup
  ```
* Assign Zabbix Template to host (Custom__Service__Postgresql__Backup.xml)
* Run initial backup
  ```
  su - postgres
  /opt/postgresql-scripts/backup-databases.sh /srv/postgresql-backup 5
  ```
