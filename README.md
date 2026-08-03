# odoo_script

## Installation

USE THIS KNOWLEDGE PAGE :

Open a terminal (CTRL + ALT + T)
run this commands:
```console
curl https://raw.githubusercontent.com/roole-odoo/odoo_script/refs/heads/main/odoo_install.sh > odoo_install.sh
chmod +x odoo_install.sh
./odoo_install.sh
```


## TODO

- ~~Script should run on 26.04 and 24.04.~~ tested on 24.04 and 26.06 -> OK
- Odoo is working well ? Odoorc, IA, all posgress changes ? Need to check on a produced db if it's running

## Explained

Script run a menu.
If debug choisen /home/odoo/Desktop/odoo_install.debug"
Log always at /var/log/odoo_installation.log (cleaned at each run,wanted ? )

## Normal Workflow Explained:

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

## FYI

If you have problem to clone Odoo repository with error  **"fatal: fetch-pack: Invalid index-pack output"** usually due to low memory
run this 2 commands and retry the install (it's already intégrated on this script)
```console
git config --global pack.threads 1
git config --global http.postBuffer 524288000```
