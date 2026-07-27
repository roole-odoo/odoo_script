#!/usr/bin/env bash
set -Eeuo pipefail
DEBUG_FILE="/home/odoo/Desktop/odoo_install.debug"
LOG="/var/log/odoo_installation.log"
DB_NAME=""

# Create a LOG file a each run
sudo -v touch "$LOG" && sudo chown "$USER" "$LOG"
: > "$LOG"


# Put the outuput of heavy cmd into LOG  (often for apt)
run() { "$@" >>"$LOG" 2>&1; }

# catch if the script crash
trap 'echo; echo "FAILED (line $LINENO). Last lines of $LOG:"; tail -n 15 "$LOG"' ERR

# Echo + in debug file
log() { echo "$*" | tee -a "$DEBUG_FILE"; }

ok()   { log "[  OK  ] $*"; }

fail()   { log "[ MISS ] $*"; } 

exists() { [[ -e "$1" ]] && ok "$1" || fail "$1"; }

# Check the repo and print the branch
repo_check() { [[ -d "$1/.git" ]] && ok "$1 ($(git -C "$1" rev-parse --abbrev-ref HEAD))" || fail "$1"; }

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		echo "  $cmd already installed."
	else
		echo "  Installing $pkg ..."
		run sudo apt-get install -y "$pkg"
		have "$cmd" || echo "  WARNING: $cmd install failed"
	fi
}


check_ssh_key() {
	local user_gram
	local ssh_key_path="/home/odoo/.ssh/id_ed25519"
	local ssh_pub_key_path="/home/odoo/.ssh/id_ed25519.pub"
	user_gram="$(cut -d '-' -f 1 </etc/hostname)"
	if [[ -f "${ssh_pub_key_path}" ]]; then
		echo "A SSH key is already created (${ssh_key_path}), be sure it's linked to your GitHub profile."
		echo "Data to be checked in GitHub user profile [https://github.com/settings/keys]:"
		echo "$(<$ssh_pub_key_path)"
	else
		echo "SSH key not found. Generating new ed25519 SSH key for '${user_gram}@odoo.com'."
		echo "Path to add the key: ${ssh_key_path}"
		ssh-keygen -t ed25519 -C "${user_gram}@odoo.com" -f "$ssh_key_path"
		echo "Add the data below to your GitHub user profile https://github.com/settings/keys:"
		echo "$(<$ssh_pub_key_path)"
	fi
	while true; do
		read -r -p "Key added to your GitHub account ? [y/N]: " answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			echo "Starting the installation in 5s ..."
			sleep 5
		else
			echo "Relaunch this script once it's done."
			exit 0
		fi
		if git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1; then
			echo "GitHub SSH access OK."
			break
		fi
		echo "ERROR: GitHub SSH key not configured yet."
	done
}


check_ubuntu() {
	. /etc/os-release # Get ID and verison varialbe
	echo "System: $ID $VERSION_ID (user $USER)"
	if [[ "$ID" != "ubuntu" ]]; then
		echo "ERROR: expected ubuntu, found: $ID. OS not supported. Exit..."
		exit 1
	fi
	if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "26.04" ]]; then
		echo "Your installation variant is not supported, expected version: '24.04' or '26.04' found: $VERSION_ID."
		exit 1
	fi
	if [[ "${USER}" != "odoo" ]]; then
		echo "ERROR: expected 'odoo' username, only OSes provided by Odoo are supported. Exit..."
		exit 1
	fi
}


check_python() {
	have python3 || {
		echo "python3 not found."
		exit 1
	}
	echo "Python: $(python3 --version)"
	python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' ||
		{
			echo "ERROR : need 3.12+."
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
	echo "  Installing wkhtmltopdf (patched qt) ..."
	run sudo dpkg -r wkhtmltox || true
	run curl -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -o /tmp/wkhtml.deb
	run sudo apt-get -y install --no-install-recommends --fix-missing /tmp/wkhtml.deb
	rm -f /tmp/wkhtml.deb
}


install_pgvector() {
	echo "  Installing pgvector ..."
	run sudo apt-get install -y "postgresql-18-pgvector"
}


install_rtlcss() {
	read -r -p "Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work on those. [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		echo "  Installing rtlcss ..."
		run sudo npm install -g rtlcss
		read -r -p "Remove NPM ? [y/N]: " answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			echo "  Removing npm ..."
			run sudo apt-get -y remove npm
		fi
	fi
}



install_deps() {
	echo "Installing system dependencies ..."
	install_cmd git
	install_cmd curl
	install_cmd psql postgresql-18
	install_wkhtmltopdf
	install_pgvector
	echo "Dependencies ready."
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
		echo "  ${home_path}src already exists, skipping clone."
	fi
	echo "  Switching repositories to master ..."
    cd "${home_path}src/odoo" && git switch master
    cd "${home_path}src/enterprise" && git switch master
    cd "${home_path}src/design-themes" && git switch master
    cd "${home_path}src/industry" && git switch master
	echo "  Installing Odoo debian dependencies (setup/debinstall.sh) ..."
	run sudo "${home_path}src/odoo/setup/debinstall.sh"
}


postgresql_setup() {
	echo "Configuring PostgreSQL ..."
	sudo systemctl enable --now postgresql
	sudo -u postgres createuser -d -R -S odoo
	sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # ALL FUTUR DB will get it
}


setup_odoorc() {
	echo "Fetching .odoorc configuration ..."
	run curl -fsSL -o /home/odoo/src/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
}


install_mailcatcher() {
	read -r -p "Need MailCatcher ? It's for having on local a mailing solution. [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		have mailcatcher && return 0
		echo "  Installing MailCatcher ..."
		run sudo apt-get install -y ruby ruby-dev
		run sudo gem install mailcatcher
	fi
}


create_database() {
	local pattern="^[0-9a-zA-Z_-]{1,60}$"
	while :; do
		read -r -p "Name of your database: " DB_NAME
		[[ $DB_NAME =~ $pattern ]] && break
		echo "Invalid name: only a-z, A-Z, 0-9, _ and - allowed."
	done
	cd /home/odoo/src/odoo
	echo "Creating database '$DB_NAME' (a few minutes) ..."
	run python3 odoo-bin -d "$DB_NAME" -i base --stop-after-init
}


set_expiration_date() {
	psql -d "$DB_NAME" >>"$LOG" 2>&1 <<-'SQL'
		INSERT INTO ir_config_parameter (key, value)
		VALUES ('database.expiration_date', '2998-05-07 13:16:50')
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
		DELETE FROM ir_config_parameter WHERE key = 'database.expiration_reason';
	SQL
	echo "Expiration date set on '$DB_NAME'."
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
	echo "Installation complete. Full log: $LOG"
}


advanced_installation() {
	check_ubuntu
	check_python
	install_deps
	install_rtlcss # right-to-left
	install_mailcatcher # mail
	check_ssh_key
	fetch_git_repositories
	postgresql_setup
	create_database
	setup_odoorc
	set_expiration_date
	echo "Installation complete. Full log: $LOG"
}

menu(){
	echo "1) Complete Install  2) Check Tools  3) Advanced Install  4) Exit"
	read -rp "Select option [1-4]: " choice
	case "$choice" in
	  1) normal_installation;;
	  2) check_deps ;;
	  3) advanced_installation;;
	  4) exit 0 ;;
	  *) echo "Invalid option"; menu ;;
	esac
}

menu
