#!/usr/bin/env bash
set -Eeuo pipefail
DEBUG_FILE="/home/odoo/Desktop/odoo_install.debug"
LOG="/var/log/odoo_installation.log"
DB_NAME=""
ADVANCED_MODE=0
UPDATE_MODE=0
ALIAS_NAME="odoo-localDB"
MANAGER_SHORTCUT_PATH="/home/odoo/Desktop/odoo_local_databases_manager.desktop"
ODOO_SHORTCUT_PATH="/home/odoo/Desktop/odoo_launcher.desktop"
USER_PASSWORD=""

RED=$'\e[31m'
GREEN=$'\e[32m'
BLUE=$'\e[34m'
ENDCOLOR=$'\e[0m'

create_log_file() {
    # Create a LOG file a each run
    echo "$USER_PASSWORD" | sudo -v -S >/dev/null 2>&1
    sudo touch "$LOG"
    sudo chown "$USER" "$LOG"
    : >"$LOG"
    sudo -k
	# Create a LOG file a each run
	echo "$USER_PASSWORD" | sudo -v -S >/dev/null 2>&1
	sudo touch "$LOG"
	sudo chown "$USER" "$LOG"
	: >"$LOG"
	sudo -k
}

# Put the outuput of heavy cmd into LOG  (often for apt)
run() { "$@" >>"$LOG" 2>&1; }

run_sudo() { echo "$USER_PASSWORD" | sudo -S -k "$@" >>"$LOG" 2>&1; }

# catch if the script crash
trap 'echo; echo "FAILED (line $LINENO). Last lines of $LOG:"; tail -n 15 "$LOG"' ERR

# Echo + in debug file
log() {
	echo -e "$*"
	echo "$(date) - $*" >>"$DEBUG_FILE"
}

ok() { log "${GREEN}[  OK  ] $*${ENDCOLOR}"; }

fail() { log "${RED}[ MISS ] $*${ENDCOLOR}"; }

exists() {
	if [[ -e "$1" ]]; then
		ok "$1"
	else
		fail "$1"
	fi
}

inputdata(){
	#clean stdin  buffer
	while read -r -t 0; do read -r; done
	read -r -p "$*" response
	echo "${response}"
}

# Check the repo and print the branch
repo_check() {
	if [[ -d "$1/.git" ]]; then
		ok "$1 ($(git -C "$1" rev-parse --abbrev-ref HEAD))"
	else
		fail "$1"
	fi
}

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		log "${BLUE}  $cmd already installed.${ENDCOLOR}"
	else
		log "${BLUE}  Installing $pkg ...${ENDCOLOR}"
		run_sudo apt-get install -y "$pkg"
		have "$cmd" || log "${RED}  WARNING: $cmd install failed${ENDCOLOR}"
	fi
}

ask_password() {
    while read -r -t 0; do read -r; done
    while ! (echo "$USER_PASSWORD" | sudo -S -k -v >/dev/null 2>&1); do
        read -r -s -p "${GREEN}Enter you password (output is silent): ${ENDCOLOR}" USER_PASSWORD
        echo ""
    done
}

check_ssh_key() {
	local user_gram
	local ssh_known_hosts_path="/home/odoo/.ssh/known_hosts"
	local ssh_key_path="/home/odoo/.ssh/id_ed25519"
	local ssh_pub_key_path="/home/odoo/.ssh/id_ed25519.pub"
	user_gram="$(cut -d '-' -f 1 </etc/hostname)"
	if [[ -f "${ssh_pub_key_path}" ]]; then
		log "${BLUE}There is already an exisiting SSH key on this system(${ssh_key_path}) ${ENDCOLOR}"
		log "${BLUE}Please make sure the public key below is referenced in your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		log "$(<$ssh_pub_key_path)"
	else
		log "${BLUE}SSH key not found. Generating new ed25519 SSH key for '${user_gram}@odoo.com'.${ENDCOLOR}"
		log "${BLUE}Path to add the key: ${ssh_key_path}${ENDCOLOR}"
		run ssh-keygen -t ed25519 -C "${user_gram}@odoo.com" -f "$ssh_key_path"
		log "${BLUE}Please add the public key below to your GitHub profile [https://github.com/settings/keys]:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	fi
	log "${BLUE}Adding Github fingerprints to known_hosts file if needed${ENDCOLOR}"
	if [[ -f "${ssh_known_hosts_path}" ]] && grep -qw "github.com" $ssh_known_hosts_path; then
		log "${BLUE}Fingerprint already present, nothing to do${ENDCOLOR}"
	else
		curl --silent https://api.github.com/meta | jq --raw-output '"github.com "+.ssh_keys[]' >>$ssh_known_hosts_path #https://docs.github.com/en/rest/meta/meta?apiVersion=2026-03-10#get-github-meta-information
	fi
	while true; do
		answer=$(inputdata "${GREEN}Have you added your public key to your GitHub account ? [y/N]: ${ENDCOLOR}")
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			log "${BLUE}Starting the installation in 5s ...${ENDCOLOR}"
			sleep 5
		else
			log "${BLUE}Please launch this script again once your key have been added to your Github account. Exit.${ENDCOLOR}"
			exit 0
		fi
		if git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1; then
			log "${BLUE}GitHub SSH access validated${ENDCOLOR}"
			break
		fi
		log "${RED}ERROR: GitHub SSH access could not be validated. Please check that you entered the right key into your Github account${ENDCOLOR}"
	done
}

check_ubuntu() {
	. /etc/os-release # Get ID and verison varialbe
	log "${BLUE}System: $ID $VERSION_ID (user $USER)${ENDCOLOR}"
	if [[ "$ID" != "ubuntu" ]]; then
		log "${RED}ERROR: expected Ubuntu, found: $ID. OS not supported. Exit...${ENDCOLOR}"
		exit 1
	fi
	if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "26.04" ]]; then
		log "${RED}Your installation variant is not supported, expected version: '24.04' or '26.04' found: $VERSION_ID.${ENDCOLOR}"
		exit 1
	fi
	if [[ "${USER}" != "odoo" ]]; then
		log "${RED}ERROR: expected 'odoo' username, only OSes provided by Odoo are supported. Exit...${ENDCOLOR}"
		exit 1
	fi
}

check_python() {
	have python3 || {
		log "${RED}python3 not found.${ENDCOLOR}"
		exit 1
	}
	log "Python: $(python3 --version)"
	python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' ||
		{
			log "${RED}ERROR : need 3.12+.${ENDCOLOR}"
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
	log "${BLUE}  Installing wkhtmltopdf (patched qt) ...${ENDCOLOR}"
	run_sudo dpkg -r wkhtmltox || true
	run curl -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -o /tmp/wkhtml.deb
	run_sudo apt-get -y install --no-install-recommends --fix-missing /tmp/wkhtml.deb
	rm -f /tmp/wkhtml.deb
}

install_pgvector() {
	log "${BLUE}  Installing pgvector ...${ENDCOLOR}"
	run_sudo apt-get install -y "postgresql-18-pgvector"
}

install_rtlcss() {
	answer=$(inputdata "${GREEN}Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work with those [y/N]: ${ENDCOLOR}")
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		log "${BLUE}  Installing rtlcss ...${ENDCOLOR}"
		run_sudo npm install -g rtlcss
		answer=$(inputdata "${GREEN}Remove NPM ? [y/N]: ${ENDCOLOR}")
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			log "${BLUE}  Removing npm ...${ENDCOLOR}"
			run_sudo apt-get -y remove npm
		fi
	fi
}

install_deps() {
	log "${BLUE}Installing system dependencies ...${ENDCOLOR}"
	install_cmd git
	install_cmd curl
	install_cmd psql postgresql-18
	install_wkhtmltopdf
	install_pgvector
	log "${BLUE}Dependencies ready.${ENDCOLOR}"
}

check_deps() {
	clear
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
	exists /home/odoo/src
	repo_check /home/odoo/src/odoo
	repo_check /home/odoo/src/enterprise
	repo_check /home/odoo/src/design-themes
	repo_check /home/odoo/src/industry
	log "--- 6. Extra dependencies ---"
	check_cmd rtlcss
	check_cmd mailcatcher
	echo "Report saved to $DEBUG_FILE"
}

clone_repository() {
	local src_path="/home/odoo/src"
	local repo_name="$1"
	log "${BLUE}  Check and clone Odoo ${repo_name} repositorie into ${src_path}\ \n  Might be long if it's the first install on your laptop, so, take a coffee... ${ENDCOLOR}"
	cd $src_path
	if [[ ! -d "$repo_name" ]]; then
		run git clone "git@github.com:odoo/${repo_name}.git"
	else
		if [[ "$UPDATE_MODE" != 1 ]]; then
			answer=$(inputdata "${GREEN}'${repo_name}' directory already exists, do you want to overwrite it ? [y/N]: ${ENDCOLOR}")
			if [[ "$answer" =~ ^[Yy]$ ]]; then
				run rm -rf "./${repo_name}"
				run git clone "git@github.com:odoo/${repo_name}.git"
			else
				log "${BLUE} Skipping clone of '${repo_name}'.${ENDCOLOR}"
			fi
		fi
	fi
}

update_repository() {
	local src_path="/home/odoo/src"
	local repo_name="$1"
	log "${BLUE}  Switching repositories ${repo_name} to master and update it ...${ENDCOLOR}"
	cd "${src_path}/${repo_name}"
	git switch master
	log "Last '${repo_name}' commit HASH : $(git rev-parse HEAD)"
	run git pull --rebase
}

fetch_git_repositories() {
	# clone ony master branch to save disk space and cloning time
	local src_path="/home/odoo/src"
	mkdir -p "${src_path}"

	clone_repository "odoo"
	clone_repository "enterprise"
	clone_repository "design-themes"
	clone_repository "industry"

	update_repository "odoo"
	update_repository "enterprise"
	update_repository "design-themes"
	update_repository "industry"

	log "${BLUE}  Installing Odoo debian dependencies (setup/debinstall.sh)${ENDCOLOR}"
	echo "${BLUE}  It might take a while ...${ENDCOLOR}"
	run_sudo "${src_path}/odoo/setup/debinstall.sh"
	return 0
}

postgresql_setup() {
	log "${BLUE}Configuring PostgreSQL ...${ENDCOLOR}"
	echo "$USER_PASSWORD" | sudo -S systemctl enable --now postgresql
	if sudo -u postgres psql -t -c '\du' | cut -f 1 -d \| | grep -qw odoo; then
		log "${BLUE} Odoo PostgreSQL User already exists. Skipping.${ENDCOLOR}"
	else
		run_sudo sudo -u postgres createuser -d -R -S odoo
	fi
	run_sudo sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # ALL FUTUR DB will get it
}

setup_odoorc() {
	log "${GREEN}Fetching .odoorc configuration ...${ENDCOLOR}"
	run curl -fsSL -o /home/odoo/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
}

install_mailcatcher() {
	answer=inputdata "${GREEN}Need MailCatcher ? It's for having on local a mailing solution. [y/N]: ${ENDCOLOR}"
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		have mailcatcher && return 0
		log "${BLUE}  Installing MailCatcher ...${ENDCOLOR}"
		run_sudo apt-get install -y ruby ruby-dev
		run_sudo gem install mailcatcher
	fi
}

create_database() {
	local pattern="^[0-9a-zA-Z_-]{1,60}$"
	while :; do
		answer=$(inputdata "${GREEN}Name of your database you want to create (leave empty to create default one named odoo): ${ENDCOLOR}")
		[[ -z "$DB_NAME" ]] && DB_NAME="odoo"
		[[ $DB_NAME =~ $pattern ]] && break
		echo "${RED}Invalid name: only a-z, A-Z, 0-9, _ and - allowed.${ENDCOLOR}"
	done
	if [[ -n "$DB_NAME" ]]; then
		cd /home/odoo/src/odoo
		log "${BLUE}Creating database '$DB_NAME' (a few minutes) ...${ENDCOLOR}"
		run python3 odoo-bin -d "$DB_NAME" -i base --stop-after-init
	fi
}

set_expiration_date() {
	log "${BLUE}Setting expiration date to 2998.${ENDCOLOR}"
	psql -d "$DB_NAME" >>"$LOG" 2>&1 <<-'SQL'
		INSERT INTO ir_config_parameter (key, value)
		VALUES ('database.expiration_date', '2998-05-07 13:16:50')
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
		DELETE FROM ir_config_parameter WHERE key = 'database.expiration_reason';
	SQL
	log "${BLUE}Expiration date set on '$DB_NAME'.${ENDCOLOR}"
}

check_memory() {
	log "${BLUE}Checking system memory.${ENDCOLOR}"
	# check laptop memory, if <= 16G change some github params to prevent clone error "fatal: fetch-pack: Invalid index-pack output"
	if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -le 16777216 ]; then
		run git config --global pack.threads 1
		run git config --global http.postBuffer 524288000
		log "${BLUE}GIT config changed to increase HTTP POST buffer.${ENDCOLOR}"
	fi
}

add_alias() { # TODO find a way to add this alias in the terminal used by the user
	if grep -qw $ALIAS_NAME /home/odoo/.bashrc; then
		log "${BLUE}Alias already exists. Skipping.${ENDCOLOR}"
	else
		log "${BLUE}Adding a bash alias${ENDCOLOR}"
		echo "alias $ALIAS_NAME='cd /home/odoo/src/odoo; python3 ./odoo-bin'" >>/home/odoo/.bashrc
	fi
}

add_desktop_shortcuts() {
	log "${BLUE}Adding desktop shortcuts${ENDCOLOR}"
	{
		echo "[Desktop Entry]"
		echo "Icon=text-html"
		echo "Name=Odoo - Local DB manager"
		echo "Type=Application"
		echo "Exec= xdg-open http://localhost:8069/web/database/manager"
	} >"${MANAGER_SHORTCUT_PATH}"

	{
		echo "[Desktop Entry]"
		echo "Exec=/home/odoo/src/odoo/odoo-bin"
		echo "GenericName=Launch Odoo Local DB"
		echo "Icon=system-run"
		echo "Name=Launch Odoo Local DB"
		echo "StartupNotify=true"
		echo "Terminal=true"
		echo "Type=Application"
	} >"$ODOO_SHORTCUT_PATH"
}

print_end_message() {
	log "${BLUE}Installation complete.${ENDCOLOR}"
	echo "${BLUE}Full log: $LOG${ENDCOLOR}"
	echo "${BLUE}To start the new DB enter this command in a new terminal:${ENDCOLOR}"
	echo "${BLUE}	cd /home/odoo/src/odoo && python3 ./odoo-bin ${ENDCOLOR}"
	echo "${BLUE}This will start your DB, that you will be able to manage on http://localhost:8069/web/database/manager (shortcut added to your desktop) ${ENDCOLOR}"
	echo "${BLUE}To end the DB, press CTRL + c${ENDCOLOR}"
}

odoo_local_installation() {
	clear
	answer=$(inputdata "${GREEN}Do you need advanced installation options ? Support for right-to-left languages (Arabic, Hebrew) and local emails service (mailcatcher). Only needed if you work with those [y/N]: ${ENDCOLOR}")
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		ADVANCED_MODE=1
	fi
	check_memory
	check_ubuntu
	check_python
	install_deps
	check_ssh_key
	if [[ "$ADVANCED_MODE" == 1 ]]; then
		install_rtlcss      # right-to-left
		install_mailcatcher # mail
	fi
	fetch_git_repositories
	postgresql_setup
	create_database
	setup_odoorc
	set_expiration_date
	add_alias
	add_desktop_shortcuts
	print_end_message
}

update_installation() {
	UPDATE_MODE=1 #Do not annoy user for overwrite questions
	clear
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
	echo "${BLUE}1) Complete Install ${ENDCOLOR}"
	echo "${BLUE}2) Check Tools (only check your laptop have all dependencies installed, if not install them) ${ENDCOLOR}"
	echo "${BLUE}3) Update this Install (update all Github repository) ${ENDCOLOR}"
	echo "${BLUE}4) Exit ${ENDCOLOR}"
	choice=$(inputdata "${GREEN}Select option [1-4]: ${ENDCOLOR}")
	case "$choice" in
	1)
		ask_password
		create_log_file
		odoo_local_installation
		;;
	2) check_deps ;;
	3)
		ask_password
		create_log_file
		update_installation
		;;
	4) exit 0 ;;
	*)
		echo "${RED}Invalid option${ENDCOLOR}"
		menu
		;;
	esac
	unset USER_PASSWORD
}

menu
