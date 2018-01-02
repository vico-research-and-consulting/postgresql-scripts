
Activate Backup
===============

```
echo "0 2 * * * postgres /opt/postgresql-scripts/backup-databases.sh /srv/postgresql-backup 5 | logger -t postgresql-backup
```
