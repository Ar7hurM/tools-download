#!/usr/bin/env bash
# Script de instalação aprimorado para ferramentas em Ubuntu
set -o nounset
set +o errexit

TIMESTAMP() { date '+%Y-%m-%d %H:%M:%S'; }
LOG() { echo -e "\n[$(TIMESTAMP)] $*"; }

# Verifica se o script está rodando como root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root (sudo). Saindo."
  exit 2
fi

# Pergunta ao usuário sobre instalação do InsightVM e BloodHound
read -rp "Deseja instalar InsightVM? (1 = sim, 2 = não): " INSIGHTVM_CHOICE
read -rp "Deseja instalar BloodHound? (1 = sim, 2 = não): " BLOODHOUND_CHOICE

# Atualiza apt e instala pacotes básicos
APT_UPDATED=0
apt_update_once() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    LOG "Atualizando índices do apt..."
    apt-get update -y || LOG "Aviso: atualização do apt falhou, continuando..."
    APT_UPDATED=1
  fi
}

try_pkg_install() {
  pkg="$1"
  LOG "Iniciando instalação (apt): $pkg"
  apt_update_once
  if apt-get install -y "$pkg"; then
    LOG "[ * ] $pkg foi instalada!"
  else
    LOG "Erro ao instalar $pkg."
  fi
}

# Verifica Python3 e instala se faltar
check_python3() {
  if command -v python3 >/dev/null 2>&1; then
    LOG "Python3 encontrado."
  else
    LOG "Python3 não encontrado. Instalando python3..."
    try_pkg_install python3
    LOG "[ * ] python3 foi instalada!"
  fi
}

# Cria e ativa ambiente virtual Python
create_and_activate_venv() {
  LOG "Criando ambiente virtual Python (venv)..."
  python3 -m venv venv
  source venv/bin/activate
  LOG "[ * ] Ambiente virtual ativado."
}

# Instala pacotes apt em paralelo
install_pkgs_parallel() {
  pkgs=(curl wget git ca-certificates lsb-release software-properties-common net-tools python3-pip pipx nmap smbclient)
  pids=()
  for pkg in "${pkgs[@]}"; do
    (try_pkg_install "$pkg") &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  LOG "[ * ] Todas instalações apt concluídas."
}

# Instala pipx via pip user, se não instalado
install_pipx() {
  if command -v pipx >/dev/null 2>&1; then
    LOG "pipx já instalado."
  else
    LOG "Instalando pipx via pip (user)..."
    python3 -m pip install --user pipx && export PATH="$PATH:$HOME/.local/bin"
    python3 -m pipx ensurepath 2>/dev/null || true
    LOG "[ * ] pipx foi instalada!"
  fi
}

# Instala NetExec via pipx
install_nxc() {
  if command -v nxc >/dev/null 2>&1 || command -v NetExec >/dev/null 2>&1; then
    LOG "NetExec já presente."
  else
    pipx install --force --include-deps "git+https://github.com/Pennyw0rth/NetExec" && LOG "[ * ] NetExec foi instalada!"
  fi
}

# Instala Metasploit via script
install_msfconsole() {
  if command -v msfconsole >/dev/null 2>&1; then
    LOG "msfconsole já instalado."
  else
    curl -sSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o /tmp/msfinstall
    chmod +x /tmp/msfinstall
    /tmp/msfinstall && LOG "[ * ] msfconsole foi instalada!"
  fi
}

# Instala InsightVM se escolhido
install_insightvm() {
  if [ "$INSIGHTVM_CHOICE" -eq 1 ]; then
    OUT="/opt/Rapid7Setup-Linux64.bin"
    mkdir -p /opt
    wget -q -O "$OUT" https://download2.rapid7.com/download/InsightVM/Rapid7Setup-Linux64.bin
    chmod +x "$OUT"
    LOG "[ * ] InsightVM instalado (arquivo em $OUT)."
  else
    LOG "Pulo instalação InsightVM conforme escolha do usuário."
  fi
}

# Instala golang-go
install_golang() {
  if command -v go >/dev/null 2>&1; then
    LOG "Go já instalado."
  else
    try_pkg_install golang-go
    LOG "[ * ] golang-go foi instalada!"
  fi
}

# Instala nuclei e httpx via go install
install_nuclei_httpx() {
  if ! command -v nuclei >/dev/null 2>&1; then
    GOBIN=/usr/local/bin go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && LOG "[ * ] nuclei foi instalada!"
  fi
  if ! command -v httpx >/dev/null 2>&1; then
    GOBIN=/usr/local/bin go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && LOG "[ * ] httpx foi instalada!"
  fi
}

# Instala responder via apt ou git clone
install_responder() {
  if command -v responder >/dev/null 2>&1 || command -v Responder >/dev/null 2>&1; then
    LOG "Responder já instalado."
  else
    if ! try_pkg_install responder; then
      TMP="/opt/responder-$$"
      rm -rf "$TMP"
      git clone https://github.com/lgandx/Responder.git "$TMP" && LOG "[ * ] Responder clonado em $TMP."
    fi
  fi
}

# Instala bloodhound via pip user se escolhido
install_bloodhound() {
  if [ "$BLOODHOUND_CHOICE" -eq 1 ]; then
    if python3 -c "import bloodhound" >/dev/null 2>&1; then
      LOG "bloodhound-python já instalado."
    else
      python3 -m pip install --user bloodhound && LOG "[ * ] bloodhound-python foi instalada!"
    fi
  else
    LOG "Pulo instalação bloodhound conforme escolha do usuário."
  fi
}

# Instala impacket via pip user
install_impacket() {
  if python3 -c "import impacket" >/dev/null 2>&1; then
    LOG "impacket já instalado."
  else
    python3 -m pip install --user impacket && LOG "[ * ] impacket foi instalada!"
  fi
}

# Instala kerbrute e terrapin scanner
install_kerbrute_terrapin() {
  LOG "Baixando kerbrute e terrapin scanner..."
  wget --progress=bar:force -O /usr/local/bin/kerbrute https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_amd64 &
  wget --progress=bar:force -O /usr/local/bin/terrapin https://github.com/RUB-NDS/Terrapin-Scanner/releases/download/v1.1.3/Terrapin_Scanner_Linux_amd64 &
  wait
  chmod +x /usr/local/bin/kerbrute /usr/local/bin/terrapin
  LOG "[ * ] kerbrute e terrapin scanner instalados."
}

# Clona wordlist do repositório correto
install_wordlists_repo() {
  local repo_dir="/opt/wordlist"
  if [ ! -d "$repo_dir" ]; then
    git clone https://github.com/Ar7hurM/wordlist.git "$repo_dir" && LOG "[ * ] Wordlists repository clonado em $repo_dir"
  else
    LOG "Wordlists repository já presente em $repo_dir"
  fi
}

# Início script
LOG "Início do script."

check_python3
create_and_activate_venv
install_pkgs_parallel
install_pipx
install_nxc
install_msfconsole
install_insightvm
install_golang
install_nuclei_httpx
install_responder
install_bloodhound
install_impacket
install_kerbrute_terrapin
install_wordlists_repo

LOG "Instalação finalizada."
