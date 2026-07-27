# odoo_scripti

## Todo list: 

- Github repositories directly on master 
- Config PSQL :

```sql
psql -d $dbname -c "update ir_config_parameter set value='2998-05-07 13:16:50' where key='database.expiration_date';"
psql -d $dbname -c "delete from ir_config_parameter where key='database.expiration_reason'"
```

- Generate a full log of the input
- Generate a function that give all the usefull information to debug
- Create a bash Menu

## Workflow Explained:

1. Check if it ubuntu 26.04 or 24.04
2. Check the Python version 3.14
3. Install dependencies : 
    - git (apt), curl (apt), postgresql-18 (apt), postgresql-18-pgvector (apt)
    - wkhtmltopdf [Deb from git](https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb)
4. Create SSH KEY 
5. \[USER ACTION\] Waiting that the user add his key to Github (loop):  Need to put Y or n
6. Test the SSH key on the Entreprise repo
7. Download odoo,entreprise,design-themes,industry to /home/odoo/src/
8. Switch to master for each
9. Install odoo deps : (./setup/debinstall.sh)
10. Setup PQSL ast service, add vector to dbname
11. \[USER ACTION\] Waiting for a DB name.
12. Download Odoorc
13. run `python3 odoo-bin -d "$db" -i base --stop-after-init
