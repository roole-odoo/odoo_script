#!/usr/bin/env bash
set -Eeuo pipefail
DEBUG_FILE="/home/odoo/Desktop/odoo_install.debug"
LOG="/var/log/odoo_installation.log"
DB_NAME=""

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
log() { echo "$*" | tee -a "$DEBUG_FILE"; }

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
	local ssh_key_path="/home/odoo/.ssh/id_ed25519"
	local ssh_pub_key_path="/home/odoo/.ssh/id_ed25519.pub"
	user_gram="$(cut -d '-' -f 1 </etc/hostname)"
	if [[ -f "${ssh_pub_key_path}" ]]; then
		echo "${BLUE}A SSH key is already created (${ssh_key_path}), be sure it's linked to your GitHub profile.${ENDCOLOR}"
		echo "${BLUE}Data to be checked in GitHub user profile [https://github.com/settings/keys]:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	else
		echo "${BLUE}SSH key not found. Generating new ed25519 SSH key for '${user_gram}@odoo.com'.${ENDCOLOR}"
		echo "${BLUE}Path to add the key: ${ssh_key_path}${ENDCOLOR}"
		ssh-keygen -t ed25519 -C "${user_gram}@odoo.com" -f "$ssh_key_path"
		echo "${GREEN}Add the data below to your GitHub user profile https://github.com/settings/keys:${ENDCOLOR}"
		echo "$(<$ssh_pub_key_path)"
	fi
	while true; do
		read -r -p "${GREEN}Key added to your GitHub account ? [y/N]: ${ENDCOLOR}" answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			echo "${BLUE}Starting the installation in 5s ...${ENDCOLOR}"
			sleep 5
		else
			echo "${BLUE}Relaunch this script once it's done.${ENDCOLOR}"
			exit 0
		fi
		if git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1; then
			echo "${BLUE}GitHub SSH access OK.${ENDCOLOR}"
			break
		fi
		echo "${RED}ERROR: GitHub SSH key not configured yet.${ENDCOLOR}"
	done
}

check_ubuntu() {
	. /etc/os-release # Get ID and verison varialbe
	echo "${BLUE}System: $ID $VERSION_ID (user $USER)${ENDCOLOR}"
	if [[ "$ID" != "ubuntu" ]]; then
		echo "${RED}ERROR: expected ubuntu, found: $ID. OS not supported. Exit...${ENDCOLOR}"
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
	read -r -p "${GREEN}Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work on those. [y/N]: ${ENDCOLOR}" answer
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
	log "--- 2. python ---"
	check_cmd python3
	log "--- 3. dependencies ---"
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

fetch_git_repositories() {
	local home_path="/home/odoo/"
	local repo
	if [[ ! -d "${home_path}src" ]]; then
		mkdir -p "${home_path}src" && cd "${home_path}src"
		git clone git@github.com:odoo/odoo.git
		git clone git@github.com:odoo/enterprise.git
		git clone git@github.com:odoo/design-themes.git
		git clone git@github.com:odoo/industry.git
	else
		echo "${BLUE}  ${home_path}src already exists, skipping clone.${ENDCOLOR}"
	fi
	echo "${BLUE}  Switching repositories to master ...${ENDCOLOR}"
	cd "${home_path}src/odoo" && git switch master
	cd "${home_path}src/enterprise" && git switch master
	cd "${home_path}src/design-themes" && git switch master
	cd "${home_path}src/industry" && git switch master
	echo "${BLUE}  Installing Odoo debian dependencies (setup/debinstall.sh) ...${ENDCOLOR}"
	run sudo "${home_path}src/odoo/setup/debinstall.sh"
}

postgresql_setup() {
	echo "${BLUE}Configuring PostgreSQL ...${ENDCOLOR}"
	sudo systemctl enable --now postgresql
	sudo -u postgres createuser -d -R -S odoo
	sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # ALL FUTUR DB will get it
}

setup_odoorc() {
	echo "${GREEN}Fetching .odoorc configuration ...${ENDCOLOR}"
	run curl -fsSL -o /home/odoo/src/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
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
		read -r -p "${GREEN}Name of your database: ${ENDCOLOR}" DB_NAME
		[[ $DB_NAME =~ $pattern ]] && break
		echo "${RED}Invalid name: only a-z, A-Z, 0-9, _ and - allowed.${ENDCOLOR}"
	done
	cd /home/odoo/src/odoo
	echo "${BLUE}Creating database '$DB_NAME' (a few minutes) ...${ENDCOLOR}"
	run python3 odoo-bin -d "$DB_NAME" -i base --stop-after-init
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

normal_installation() {
	check_ubuntu
	check_python
	install_deps
	check_ssh_key
	fetch_git_repositories
	postgresql_setup
	setup_odoorc
	create_database
	set_expiration_date
	echo "${BLUE}Installation complete. Full log: $LOG${ENDCOLOR}"
}

advanced_installation() {
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
	echo "${BLUE}Installation complete. Full log: $LOG${ENDCOLOR}"
}

menu() {
	echo "${BLUE}1) Complete Install  2) Check Tools  3) Advanced Install  4) Exit${ENDCOLOR}"
	read -rp "${GREEN}Select option [1-4]: ${ENDCOLOR}" choice
	case "$choice" in
	1) normal_installation ;;
	2) check_deps ;;
	3) advanced_installation ;;
	4) exit 0 ;;
	*)
		echo "${RED}Invalid option${ENDCOLOR}"
		menu
		;;
	esac
}

menu
