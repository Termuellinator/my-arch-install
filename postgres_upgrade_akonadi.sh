#! /bin/sh
systemctl stop postgresql.service
akonadictl stop
mv /home/termy/.local/share/akonadi/db_data /home/termy/.local/share/akonadi/db_data.old
initdb --locale=C.UTF-8 --encoding=UTF8 -D /home/termy/.local/share/akonadi/db_data 
pg_upgrade -b /opt/pgsql-14/bin -B /usr/bin -d /home/termy/.local/share/akonadi/db_data.old -D /home/termy/.local/share/akonadi/db_data
systemctl start postgresql.service
akonadictl start
