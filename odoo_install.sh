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

  local version
  version=$(python3 -c 'import sys; print("%d.%02d" % sys.version_info[:2])')
  echo "Python: $version"

  if [[ $(echo "${version} < 3.12" | bc) == 1 ]]; then
    echo "ERROR : need 3.12+."
    exit 1
  fi
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
  sudo apt autoremove
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



fetch_git_repositories(){
  mkdir -p ~/src && cd ~/src
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/odoo.git
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/enterprise.git
  git clone --depth 1 --single-branch --branch master git@github.com:odoo/design-themes.git
  git clone --depth 1 --single-branch --branch saas-18.4 git@github.com:odoo/industry.git
  (cd ~/src/odoo && sudo ./setup/debinstall.sh)
}


postgresql_setup(){
  sudo systemctl start postgresql
  sudo systemctl enable postgresql
  sudo -u postgres createuser -d -R -S $USER
}


main(){
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
