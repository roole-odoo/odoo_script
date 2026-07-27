#!/usr/bin/env bash
set -euo pipefail
DEBUG_FILE="/home/odoo/Desktop/odoo_install.debug"
DB_NAME=""

log() { echo "$*" | tee -a "$DEBUG_FILE"; }
ok()   { log "[  OK  ] $*"; }
fail()   { log "[ MISS ] $*"; }
exists() { [[ -e "$1" ]] && ok "$1" || fail "$1"; }
repo_check() { [[ -d "$1/.git" ]] && ok "$1 ($(git -C "$1" rev-parse --abbrev-ref HEAD))" || fail "$1"; }
have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		echo " $cmd installed."
	else
		echo "$cmd missing, installing $pkg"
		sudo apt-get install -y -qq "$pkg"
		have "$cmd" || echo "$cmd install failed"
	fi
}

#=== Check dependencies ===
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
	echo "$ID : $VERSION_ID"
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
	fi
	local out
	out=$("$cmd" --version 2>&1 | head -1)
	log ""
	ok "$cmd Installed"
	log "VERSION : $out"
	log ""
}

#=== Install dependencies ===
install_wkhtmltopdf() {
	wkhtmltopdf --version 2>/dev/null | grep -q "with patched qt" && return 0
	sudo dpkg -r wkhtmltox 2>/dev/null || true
	curl -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -o /tmp/wkhtml.deb
	sudo apt-get -y install --no-install-recommends --fix-missing -qq /tmp/wkhtml.deb
	rm -f /tmp/wkhtml.deb
}

install_pgvector() {
	sudo apt-get install -y -qq "postgresql-18-pgvector"
}

install_rtlcss() {
	read -r -p "Need RTLCSS ? It's for the Odoo interface for right-to-left languages (Arabic, Hebrew). Only needed if you work on those. [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		sudo npm install -g rtlcss
		read -r -p "Remove NPM ? [y/N]: " answer

		if [[ "$answer" =~ ^[Yy]$ ]]; then
			sudo apt-get -y -qq remove npm
		fi
	fi
}

install_deps() {
	install_cmd git
	install_cmd curl
	install_cmd psql postgresql-18
	install_wkhtmltopdf
	install_pgvector
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
}

#=== GIT PART ===

fetch_git_repositories() {
	local home_path="/home/odoo/"
	if [[ ! -d "${home_path}src" ]]; then
		mkdir -p "${home_path}src" && cd "${home_path}src"
		git clone git@github.com:odoo/odoo.git
		git clone git@github.com:odoo/enterprise.git
		git clone git@github.com:odoo/design-themes.git
		git clone git@github.com:odoo/industry.git
	fi
	cd "${home_path}src/odoo" && git switch master
	cd "${home_path}src/enterprise" && git switch master
	cd "${home_path}src/design-themes" && git switch master
	cd "${home_path}src/industry" && git switch master
	(cd "${home_path}src/odoo" && sudo ./setup/debinstall.sh)
}

postgresql_setup() {
	sudo systemctl enable --now postgresql
	sudo -u postgres createuser -d -R -S odoo
	sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # Add to template1 ALL FUTUR DB will get it

}

setup_odoorc() {
	curl -fsSL -o /home/odoo/src/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
}

install_mailcatcher() {
	read -r -p "Need MailCatcher ? It's for having on local a mailing solution. [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		have mailcatcher && return 0
		sudo apt-get install -y -qq ruby ruby-dev
		sudo gem install mailcatcher
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
	python3 odoo-bin -d "$DB_NAME" -i base --stop-after-init
}
set_expiration_date() {
	psql -d "$DB_NAME" <<-'EOF'
		INSERT INTO ir_config_parameter (key, value)
		VALUES ('database.expiration_date', '2998-05-07 13:16:50')
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

		DELETE FROM ir_config_parameter WHERE key = 'database.expiration_reason';
	EOF
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
}

advanced_installation() {
	check_ubuntu
	check_python
	install_deps
	install_rtlcss # left-to-right 
	install_mailcatcher # mail
	check_ssh_key
	fetch_git_repositories
	postgresql_setup
	create_database
	setup_odoorc
	set_expiration_date
}


echo "1) Complete Install  2) Check Tools  3) Advanced Install  4) Exit"
read -rp "Select option [1-4]: " choice

case "$choice" in
  1) normal_installation;;
  2) check_deps ;;
  3) advanced_installation;;
  4) exit 0 ;;
  *) echo "Invalid option" ;;
esac

