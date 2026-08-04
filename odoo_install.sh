#!/usr/bin/env bash
set -Eeuo pipefail
DEBUG_FILE="$HOME/Desktop/odoo_install.debug"
LOG="/var/log/odoo_installation.log"
DB_NAME=""
ALIAS_NAME="odoo-localDB"
MANAGER_SHORTCUT_PATH="$HOME/Desktop/odoo_local_databases_manager.desktop"
ODOO_SHORTCUT_PATH="$HOME/Desktop/odoo_launcher.desktop"

RED=$'\e[31m'
GREEN=$'\e[32m'
BLUE=$'\e[34m'
ENDCOLOR=$'\e[0m'

# Create a LOG file a each run
sudo -v && sudo touch "$LOG" && sudo chown "$USER" "$LOG"
: >"$LOG"

# Put the outuput of heavy cmd into LOG  (often for apt)
run() { "$@" >>"$LOG" 2>&1; }

# catch if the script crash
trap 'echo; echo "FAILED (line $LINENO). Last lines of $LOG:"; tail -n 15 "$LOG"' ERR

# Echo + in debug file
log() { echo "$(date) - $*" | tee -a "$DEBUG_FILE"; }

ok() { log "${GREEN}[  OK  ] $*${ENDCOLOR}"; }

fail() { log "${RED}[ MISS ] $*${ENDCOLOR}"; }

exists() { [[ -e "$1" ]] && ok "$1" || fail "$1"; }

# Check the repo and print the branch
repo_check() { [[ -d "$1/.git" ]] && ok "$1 ($(git -C "$1" rev-parse --abbrev-ref HEAD))" || fail "$1"; }

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		echo "${BLUE}  $cmd already installed.${ENDCOLOR}"
	else
		echo "${BLUE}  Installing $pkg ...${ENDCOLOR}"
		run sudo apt-get install -y "$pkg"
		have "$cmd" || echo "${RED}  WARNING: $cmd install failed${ENDCOLOR}"
	fi
}

check_ssh_key() {
	local user_gram
	local ssh_known_hosts_path="$HOME/.ssh/known_hosts"
	local ssh_key_path="$HOME/.ssh/id_ed25519"
	local ssh_pub_key_path="$HOME/.ssh/id_ed25519.pub"
	user_gram="$(cut -d '-' -f 1 </etc/hostname)"
	if [[ -f "${ssh_pub_key_path}" ]]; then
		echo "${BLUE}There is already an exisiting SSH key on this system(${ssh_key_path}) ${ENDCOLOR}"
		echo "${BLUE}Please make sure the public key below is referenced in your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	else
		echo "${BLUE}SSH key not found. Generating new ed25519 SSH key for '${user_gram}@odoo.com'.${ENDCOLOR}"
		echo "${BLUE}Path to add the key: ${ssh_key_path}${ENDCOLOR}"
		ssh-keygen -t ed25519 -C "${user_gram}@odoo.com" -f "$ssh_key_path"
		echo "${BLUE}Please add the public key below to your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	fi
	echo "${BLUE}Adding Github fingerprints to known_hosts file if needed${ENDCOLOR}"
		if [[ -f "${ssh_known_hosts_path}" ]] && grep -qw "github.com" $ssh_known_hosts_path; then
			echo "${BLUE}Fingerprint already present, nothing to do${ENDCOLOR}"
		else
			curl --silent https://api.github.com/meta | jq --raw-output '"github.com "+.ssh_keys[]' >> $ssh_known_hosts_path #https://docs.github.com/en/rest/meta/meta?apiVersion=2026-03-10#get-github-meta-information
		fi
	while true; do
		read -r -p "${GREEN}Have you added your public key to your GitHub account ? [y/N]: ${ENDCOLOR}" answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			echo "${BLUE}Starting the installation in 5s ...${ENDCOLOR}"
			sleep 5
		else
			echo "${BLUE}Please launch this script again once your key have been added to your Github account${ENDCOLOR}"
			exit 0
		fi
		if git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1; then
			echo "${BLUE}GitHub SSH access validated${ENDCOLOR}"
			break
		fi
		echo "${RED}ERROR: GitHub SSH access could not be validated. Please check that you entered the right key into your Github account${ENDCOLOR}"
	done
}

check_ubuntu() {
	. /etc/os-release # Get ID and verison varialbe
	echo "${BLUE}System: $ID $VERSION_ID (user $USER)${ENDCOLOR}"
	if [[ "$ID" != "ubuntu" ]]; then
		echo "${RED}ERROR: expected Ubuntu, found: $ID. OS not supported. Exit...${ENDCOLOR}"
		exit 1
	fi
	if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "26.04" ]]; then
		echo "${RED}Your installation variant is not supported, expected version: '24.04' or '26.04' found: $VERSION_ID.${ENDCOLOR}"
		exit 1
	fi
	if [[ "${USER}" != "odoo" ]]; then
		echo "${RED}ERROR: expected 'odoo' username, only OSes provided by Odoo are supported. Exit...${ENDCOLOR}"
		exit 1
	fi
}

check_python() {
	have python3 || {
		echo "${RED}python3 not found.${ENDCOLOR}"
		exit 1
	}
	echo "Python: $(python3 --version)"
	python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' ||
		{
			echo "${RED}ERROR : need 3.12+.${ENDCOLOR}"
			exit 1
		}
}

check_cmd() {
	local cmd="$1"
	if ! have "$cmd"; then
		fail "$cmd not installed"
		return
	fi
	local out
	out=$("$cmd" --version 2>&1 | head -1)
	log ""
	ok "$cmd Installed"
	log "VERSION : $out"
	log ""
}

install_wkhtmltopdf() {
	wkhtmltopdf --version 2>/dev/null | grep -q "with patched qt" && return 0
	echo "${BLUE}  Installing wkhtmltopdf (patched qt) ...${ENDCOLOR}"
	run sudo dpkg -r wkhtmltox || true
	run curl -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -o /tmp/wkhtml.deb
	run sudo apt-get -y install --no-install-recommends --fix-missing /tmp/wkhtml.deb
	rm -f /tmp/wkhtml.deb
}

install_pgvector() {
	echo "${BLUE}  Installing pgvector ...${ENDCOLOR}"
	run sudo apt-get install -y "postgresql-18-pgvector"
}

install_rtlcss() {
	read -r -p "${GREEN}Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work with those [y/N]: ${ENDCOLOR}" answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		echo "${BLUE}  Installing rtlcss ...${ENDCOLOR}"
		run sudo npm install -g rtlcss
		read -r -p "${GREEN}Remove NPM ? [y/N]: ${ENDCOLOR}" answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			echo "${BLUE}  Removing npm ...${ENDCOLOR}"
			run sudo apt-get -y remove npm
		fi
	fi
}

install_deps() {
	echo "${BLUE}Installing system dependencies ...${ENDCOLOR}"
	install_cmd git
	install_cmd curl
	install_cmd psql postgresql-18
	install_wkhtmltopdf
	install_pgvector
	echo "${BLUE}Dependencies ready.${ENDCOLOR}"
}

check_deps() {
	log "--- 1. System ---"
	. /etc/os-release
	log "OS       : $ID $VERSION_ID"
	log "User     : $USER"
	log "--- 2. Python ---"
	check_cmd python3
	log "--- 3. Dependencies ---"
	check_cmd git
	check_cmd curl
	check_cmd psql
	check_cmd wkhtmltopdf
	log "--- 4. Folders ---"
	exists $HOME/src
	repo_check $HOME/src/odoo
	repo_check $HOME/src/enterprise
	repo_check $HOME/src/design-themes
	repo_check $HOME/src/industry
	log "--- 6. Extra dependencies ---"
	check_cmd rtlcss
	check_cmd mailcatcher
	echo "Report saved to $DEBUG_FILE"
}

fetch_git_repositories() {
	# clone ony master branch to save disk space and cloning time
	local home_path="$HOME/src"
	echo "${BLUE}Check and clone Odoo repositories into ${home_path} (might be long if it's the first install on your laptop, so, take a coffee)... ${ENDCOLOR}"
	mkdir -p "${home_path}"
	cd "${home_path}"

	if [[ ! -d "${home_path}/odoo" ]]; then
		git clone --single-branch --branch master git@github.com:odoo/odoo.git
	else
		echo "${BLUE}  ${home_path}/odoo already exists, skipping clone.${ENDCOLOR}"
	fi

	if [[ ! -d "${home_path}/enterprise" ]]; then
		git clone --single-branch --branch master git@github.com:odoo/enterprise.git
	else
		echo "${BLUE}  ${home_path}/enterprise already exists, skipping clone.${ENDCOLOR}"
	fi

	if [[ ! -d "${home_path}/design-themes" ]]; then
		git clone --single-branch --branch master git@github.com:odoo/design-themes.git
	else
		echo "${BLUE}  ${home_path}/design-themes already exists, skipping clone.${ENDCOLOR}"
	fi

	if [[ ! -d "${home_path}/industry" ]]; then
		git clone --single-branch --branch master git@github.com:odoo/industry.git
	else
		echo "${BLUE}  ${home_path}/industry already exists, skipping clone.${ENDCOLOR}"
	fi

	echo "${BLUE}  Switching repositories to master and update it ...${ENDCOLOR}"
	cd "${home_path}/odoo" && git switch master && log "Last odoo commit HASH : $(git rev-parse HEAD)" && git pull --rebase
	cd "${home_path}/enterprise" && git switch master && log "Last enterprise commit HASH : $(git rev-parse HEAD)" && git pull --rebase
	cd "${home_path}/design-themes" && git switch master && log "Last design-themes commit HASH : $(git rev-parse HEAD)" && git pull --rebase
	cd "${home_path}/industry" && git switch master && log "Last odoo industry HASH : $(git rev-parse HEAD)" && git pull --rebase
	echo "${BLUE}  Installing Odoo debian dependencies (setup/debinstall.sh)${ENDCOLOR}"
	echo "${BLUE}  It might take a while ...${ENDCOLOR}"
	run sudo "${home_path}/odoo/setup/debinstall.sh"
	return 0
}

postgresql_setup() {
	echo "${BLUE}Configuring PostgreSQL ...${ENDCOLOR}"
	sudo systemctl enable --now postgresql
	if sudo -u postgres psql -t -c '\du' | cut -f 1 -d \| | grep -qw odoo; then
		echo "${BLUE} Odoo PostgreSQL User already exists. Skipping.${ENDCOLOR}"
	else
		sudo -u postgres createuser -d -R -S odoo
	fi
	sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # ALL FUTUR DB will get it
}

setup_odoorc() {
	echo "${GREEN}Fetching .odoorc configuration ...${ENDCOLOR}"
	run curl -fsSL -o $HOME/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
}

install_mailcatcher() {
	read -r -p "${GREEN}Need MailCatcher ? It's for having on local a mailing solution. [y/N]: ${ENDCOLOR}" answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		have mailcatcher && return 0
		echo "${BLUE}  Installing MailCatcher ...${ENDCOLOR}"
		run sudo apt-get install -y ruby ruby-dev
		run sudo gem install mailcatcher
	fi
}

create_database() {
	local pattern="^[0-9a-zA-Z_-]{1,60}$"
	while :; do
		read -r -p "${GREEN}Name of your database you want to create (leave empty to create default one named odoo): ${ENDCOLOR}" DB_NAME
		[[ -z "$DB_NAME" ]] && DB_NAME="odoo"
		[[ $DB_NAME =~ $pattern ]] && break
		echo "${RED}Invalid name: only a-z, A-Z, 0-9, _ and - allowed.${ENDCOLOR}"
	done
	if [[ -n "$DB_NAME" ]]; then
		cd $HOME/src/odoo
		echo "${BLUE}Creating database '$DB_NAME' (a few minutes) ...${ENDCOLOR}"
		run python3 odoo-bin -d "$DB_NAME" -i base --stop-after-init
	fi
}

set_expiration_date() {
	psql -d "$DB_NAME" >>"$LOG" 2>&1 <<-'SQL'
		INSERT INTO ir_config_parameter (key, value)
		VALUES ('database.expiration_date', '2998-05-07 13:16:50')
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
		DELETE FROM ir_config_parameter WHERE key = 'database.expiration_reason';
	SQL
	echo "${BLUE}Expiration date set on '$DB_NAME'.${ENDCOLOR}"
}

check_memory(){
	# check laptop memory, if <= 16G change some github params to prevent clone error "fatal: fetch-pack: Invalid index-pack output"
	if [ $(awk '/MemTotal/ {print $2}' /proc/meminfo) -le 16777216 ]; then
		git config --global pack.threads 1
		git config --global http.postBuffer 524288000
	fi
}

add_alias(){ # TODO find a way to add this alias in the terminal used by the user
	if grep -qw $ALIAS_NAME $HOME/.bashrc; then
 		echo "${BLUE}Alias already exists. Skipping.${ENDCOLOR}"
	else
		echo "${BLUE}Adding a bash alias${ENDCOLOR}"
		echo "alias $ALIAS_NAME='cd $HOME/src/odoo; ./odoo-bin -d ${DB_NAME}'" >> $HOME/.bashrc
	fi
}

add_desktop_shortcuts(){
	echo "${BLUE}Adding desktop shortcuts${ENDCOLOR}"

	echo "[Desktop Entry]" > "${MANAGER_SHORTCUT_PATH}" #Not appending so that we can re-run the script and rewrite the shortcut everytime
	echo "Icon=text-html" >> "${MANAGER_SHORTCUT_PATH}"
	echo "Name=Odoo - Local DB manager" >> "${MANAGER_SHORTCUT_PATH}"
	echo "Type=Application" >> "${MANAGER_SHORTCUT_PATH}"
	echo "Exec= xdg-open http://localhost:8069/web/database/manager" >> "${MANAGER_SHORTCUT_PATH}"

	echo "[Desktop Entry]" > "${ODOO_SHORTCUT_PATH}"
	echo "Exec=$HOME/src/odoo/odoo-bin" >> "${ODOO_SHORTCUT_PATH}"
	echo "GenericName=Launch Odoo Local DB" >> "${ODOO_SHORTCUT_PATH}"
	echo "Icon=system-run" >> "${ODOO_SHORTCUT_PATH}"
	echo "Name=Launch Odoo Local DB" >> "${ODOO_SHORTCUT_PATH}"
	echo "StartupNotify=true" >> "${ODOO_SHORTCUT_PATH}"
	echo "Terminal=true" >> "${ODOO_SHORTCUT_PATH}"
	echo "Type=Application" >> "${ODOO_SHORTCUT_PATH}"
}

normal_installation() {
	check_memory
	check_ubuntu
	check_python
	install_deps
	check_ssh_key
	fetch_git_repositories
	postgresql_setup
	setup_odoorc
	create_database
	set_expiration_date
	add_alias
	add_desktop_shortcuts
	echo "${BLUE}Installation complete. Full log: $LOG${ENDCOLOR}"
	echo "${BLUE}To start the new DB enter this command in a new terminal:${ENDCOLOR}"
	echo "${BLUE}	${ALIAS_NAME} ${ENDCOLOR}"
	echo "${BLUE}This will start your DB, that you will be able to manage on http://localhost:8069/web/database/manager (shortcut added to your desktop) ${ENDCOLOR}"
	echo "${BLUE}To end the DB, press CTRL + c${ENDCOLOR}"
}

advanced_installation() {
	check_memory
	check_ubuntu
	check_python
	install_deps
	install_rtlcss      # right-to-left
	install_mailcatcher # mail
	check_ssh_key
	fetch_git_repositories
	postgresql_setup
	create_database
	setup_odoorc
	set_expiration_date
	add_alias
	add_desktop_shortcuts
	echo "${BLUE}Installation complete. Full log: $LOG${ENDCOLOR}"
	echo "${BLUE}To start the new DB enter this command in a new terminal:${ENDCOLOR}"
	echo "${BLUE}	${ALIAS_NAME} ${ENDCOLOR}"
	echo "${BLUE}This will start your DB, that you will be able to manage on http://localhost:8069/web/database/manager (shortcut added to your desktop)${ENDCOLOR}"
	echo "${BLUE}To end the DB, press CTRL + c${ENDCOLOR}"
}

extra_installation() {
	check_memory
	check_ubuntu
	check_python
	install_deps
	install_rtlcss      # right-to-left
	install_mailcatcher # mail
}

update_installation(){
	check_memory
	check_ubuntu
	check_python
	install_deps
	check_ssh_key
	fetch_git_repositories
}

menu() {
	echo "${BLUE}Odoo Local Database installer${ENDCOLOR}"
	echo "${BLUE}#############################${ENDCOLOR}"
	echo "${BLUE}Documentation: https://www.odoo.com/odoo/knowledge/18175 ${ENDCOLOR}"
	echo  "${BLUE}1) Complete Install (Normal process, for every one) ${ENDCOLOR}"
	echo  "${BLUE}2) Check Tools (only check your laptop have all dependencies is installed, if not install them) ${ENDCOLOR}"
	echo  "${BLUE}3) Extra Install (install rtlcss (right-to-left option for Arabic and Hebrew languages) and mailcatcher) ${ENDCOLOR}"
	echo  "${BLUE}4) Update this Install (update all Github repository) ${ENDCOLOR}"
	echo  "${BLUE}5) Exit ${ENDCOLOR}"
	read -rp "${GREEN}Select option [1-5]: ${ENDCOLOR}" choice
	case "$choice" in
	1) normal_installation ;;
	2) check_deps ;;
	3) extra_installation ;;
	4) update_installation ;;
	5) exit 0 ;;
	*)
		echo "${RED}Invalid option${ENDCOLOR}"
		menu
		;;
	esac
}

menu
