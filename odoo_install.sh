#!/usr/bin/env bash
set -euo pipefail

#=== utilities function ===
usage() {
  cat <<EOF
Usage: $(basename "$0") blabla



EOF
}

check_help(){
    [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; } # check the --help  TODO make a better args parser
}

have() { command -v "$1" >/dev/null 2>&1; } # Check a cmd


install_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  if have "$cmd"; then
    echo " $cmd installed."
  else
    echo "$cmd missing, installing $pkg"
    sudo apt-get install -y -qq "$pkg"
    have $cmd || echo "$cmd installed"
  fi
}

#=== Check dependencies ===
check_ubuntu() {
  . /etc/os-release    # Get ID and verison varialbe
  echo "$ID : $VERSION_ID"
  if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "26.04" ]]; then
    echo "ERROR: expected Ubuntu 26.04, found $ID $VERSION_ID. Exit..."
    exit 1
  fi
  if [[ "${USER}" != "odoo" ]]
  then
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

check_cmd(){
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

install_rtlcss(){
  install_cmd npm
  sudo npm install -g rtlcss
  sudo apt-get -y remove npm
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


check_deps(){
  check_cmd python3
  check_cmd git
  check_cmd curl
  check_cmd rtlcss
  check_cmd psql
  check_cmd wkhtmltopdf
}


#=== GIT PART ===


# TODO No more git switch ? 
fetch_git_repositories(){
  mkdir -p ~/src && cd ~/src
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/odoo.git
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/enterprise.git
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/design-themes.git
  git clone --depth 1 --single-branch --branch master  git@github.com:odoo/industry.git
  (cd ~/src/odoo && sudo ./setup/debinstall.sh)
}



# TODO PiPE working ? 
postgresql_setup() {
  sudo systemctl enable --now postgresql
  sudo -u postgres createuser -d -R -S "$USER" 2>/dev/null
  sudo -u postgres psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS vector;" # Add to template1 ALL FUTUR DB will get it
}

# TODO Question Still the rigth one industry ?
setup_odoorc() {
  [[ -f ~/.odoorc ]] && return 0
  curl -fsSL -o ~/.odoorc https://gist.githubusercontent.com/Abridbus/a4c1ada1e8c61c04ab68cc8ddbb827b1/raw/4614022d0c21bbc02f35254d59c5cefcdbedb12d/.odoorc
}

# TODO GEM is the new NPM ? More explanation 
install_mailcatcher() {
  have mailcatcher && return 0
  sudo apt-get install -y -qq ruby ruby-dev
  sudo gem install mailcatcher
}



# TODO Odoo init db creation 
create_database() {
  local db="${1:-odoo_master}"
  cd ~/src/odoo
  python3 odoo-bin -d "$db" -i base --stop-after-init
}

main(){
  check_ubuntu
  check_python
  check_ssh_key
  install_deps
  check_deps
  fetch_git_repositories
  postgresql_setup
  setup_odoorc
  #create_database
}

main
