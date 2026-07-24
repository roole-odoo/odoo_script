#!/usr/bin/env bash
set -euo pipefail

#=== utilities function ===
usage() {
	cat <<EOF
Usage: $(basename "$0") blabla



EOF
}

check_help() {
	[[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]] && {
		usage
		exit 0
	} # check the --help  TODO make a better args parser
}

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd

install_cmd() {
	local cmd="$1" pkg="${2:-$1}"
	if have "$cmd"; then
		echo " $cmd installed."
	else
		echo "$cmd missing, installing $pkg"
		sudo apt-get install -y -qq "$pkg"
		have "$cmd" || echo "$cmd installed"
	fi
}

#=== Check dependencies ===
check_env() {
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
		echo "Data to be added in GitHub user profile [https://github.com/settings/keys](New SSH key):"
		echo "$(<$ssh_pub_key_path)"

	fi
	read -r -p "Key added to your GitHub account ? [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		echo "Starting the installation in 5s ..."
		sleep 5
	else
		echo "Relaunch this script once it's done."
		exit 0
	fi
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
  have python3 || { echo "python3 not found."; exit 1; }
  echo "Python: $(python3 --version)"
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' \
    || { echo "ERROR : need 3.12+."; exit 1; }
}

check_cmd() {
	local cmd="$1"
	if ! have "$cmd"; then
		echo "$cmd not installed"
		exit 1
	fi
	local out
	out=$("$cmd" --version 2>&1 | head -1)
	echo ""
	echo "=== $cmd Installed | VERSION: ==="
	echo "$out"
	echo ""
}


check_ssh_key() {
git ls-remote git@github.com:odoo/enterprise.git HEAD >/dev/null 2>&1 || (echo "ERROR: GitHub SSH key not configured."; exit 1)
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
	read -r -p "Need 'left-to-right' compatibility ? [y/N]: " answer
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		install_cmd npm
		sudo npm install -g rtlcss
		read -r -p "Remove NPM ? [y/N]: " answer

		if [[ "$answer" =~ ^[Yy]$ ]]; then
			sudo apt-get -y -qq remove npm
		fi
	fi
}



install_deps(){
  install_cmd git
  install_cmd curl
  install_cmd psql postgresql-18
  install_wkhtmltopdf
  install_pgvector
  install_rtlcss
  sudo apt  autoremove -y -qq --purge
}

check_deps() {
	check_cmd python3
	check_cmd git
	check_cmd curl
	check_cmd rtlcss
	check_cmd psql
	check_cmd wkhtmltopdf
}

#=== GIT PART ===

fetch_git_repositories() {
	local home_path="/home/odoo/"
	mkdir -p "${home_path}src" && cd "${home_path}src"
	git clone git@github.com:odoo/odoo.git
	git clone git@github.com:odoo/enterprise.git
	git clone git@github.com:odoo/design-themes.git
	git clone git@github.com:odoo/industry.git
	(cd "${home_path}src" && sudo ./setup/debinstall.sh)
}

postgresql_setup() {
	sudo systemctl start postgresql
	sudo systemctl enable postgresql
	sudo -u postgres createuser -d -R -S odoo
}

main() {
	check_env
	check_ubuntu
	check_python

	# install dependencies
	install_deps

	# Check dependencie
	#
	#
	check_deps
}

main
