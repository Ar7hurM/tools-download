#!/usr/bin/env bash
# install-ubuntu-tools.sh
# Script para Ubuntu (apt). Uso: sudo ./install-ubuntu-tools.sh
set -o nounset
set +o errexit   # não sair no primeiro erro; tratamos retornos manualmente

TIMESTAMP(){ date '+%Y-%m-%d %H:%M:%S'; }
LOG(){ echo -e "\n[$(TIMESTAMP)] $*"; }

# verifica root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root (sudo). Saindo."
  exit 2
fi

APT_UPDATED=0
apt_update_once() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    LOG "Atualizando índices do apt..."
    apt-get update -y || LOG "Aviso: apt-get update retornou erro, continuando..."
    APT_UPDATED=1
  fi
}

try_pkg_install() {
  pkg="$1"
  LOG "Iniciando instalação (apt): $pkg"
  apt_update_once
  if apt-get install -y "$pkg"; then
    LOG "OK: pacote $pkg instalado com sucesso."
    return 0
  else
    LOG "ERRO: falha ao instalar pacote $pkg via apt."
    return 1
  fi
}

run_and_report_cmd() {
  label="$1"; shift
  LOG "Executando comando: $label"
  if "$@"; then
    LOG "OK: $label concluído com sucesso."
    return 0
  else
    LOG "ERRO: $label falhou."
    return 1
  fi
}

LOG "Iniciando processo de instalação das ferramentas."

# instalar utilitários básicos
apt_update_once
try_pkg_install curl || true
try_pkg_install wget || true
try_pkg_install git || true
try_pkg_install ca-certificates || true
try_pkg_install lsb-release || true
try_pkg_install software-properties-common || true

# 1) net-tools
try_pkg_install net-tools || true

# 2) python3
try_pkg_install python3 || true

# 3) python3-pip
if command -v pip3 >/dev/null 2>&1; then
  LOG "pip3 já disponível."
else
  try_pkg_install python3-pip || {
    LOG "Tentando instalar pip3 via get-pip.py"
    if command -v curl >/dev/null 2>&1; then
      if curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && python3 /tmp/get-pip.py; then
        LOG "pip3 instalado via get-pip.py"
        rm -f /tmp/get-pip.py
      else
        LOG "Falha ao instalar pip3 via get-pip.py"
      fi
    else
      LOG "curl não disponível; não consegui baixar get-pip.py"
    fi
  }
fi

# comando pip seguro
PIP_CMD="python3 -m pip"

# 4) pipx
if command -v pipx >/dev/null 2>&1; then
  LOG "pipx já instalado."
else
  LOG "Tentando instalar pipx via apt..."
  if try_pkg_install pipx; then
    LOG "pipx instalado via apt."
  else
    LOG "Tentando instalar pipx via pip (user)..."
    if $PIP_CMD install --user pipx; then
      LOG "pipx instalado (user). Adicionando ~/.local/bin ao PATH temporariamente."
      export PATH="$PATH:$HOME/.local/bin"
      python3 -m pipx ensurepath 2>/dev/null || true
    else
      LOG "Falha ao instalar pipx via pip."
    fi
  fi
fi

# garantir path de user-installs
export PATH="$PATH:$HOME/.local/bin:/usr/local/bin"

# 5) nxc (NetExec) - via pipx
LOG "Instalando NetExec (nxc) via pipx (git+https)..."
if command -v nxc >/dev/null 2>&1 || command -v NetExec >/dev/null 2>&1; then
  LOG "NetExec já presente no PATH."
else
  if command -v pipx >/dev/null 2>&1; then
    run_and_report_cmd "pipx install NetExec (GitHub)" pipx install --force --include-deps "git+https://github.com/Pennyw0rth/NetExec" || LOG "pipx install NetExec falhou; verifique manualmente."
  else
    LOG "pipx não disponível; não consegui instalar NetExec automaticamente."
  fi
fi

# 6) msfconsole (Metasploit) - conforme comando fornecido pelo usuário
LOG "Instalando Metasploit (msfconsole) usando o instalador rápido (msfinstall)."
if command -v msfconsole >/dev/null 2>&1; then
  LOG "msfconsole já instalado."
else
  LOG "Baixando msfinstall e executando (isso instalará o Metasploit Framework)."
  if run_and_report_cmd "curl -> msfinstall" bash -c "curl -sSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall && chmod 755 /tmp/msfinstall && /tmp/msfinstall"; then
    LOG "msfconsole instalado (ou atualização concluída)."
  else
    LOG "Falha ao executar msfinstall. Verifique logs acima. Você pode tentar manualmente:"
    LOG "  curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall"
  fi
fi

# 7) InsightVM - wget + chmod conforme solicitado
LOG "Baixando InsightVM installer (Rapid7) e tornando executável: Rapid7Setup-Linux64.bin"
INSIGHT_URL="https://download2.rapid7.com/download/InsightVM/Rapid7Setup-Linux64.bin"
OUT="/opt/Rapid7Setup-Linux64.bin"
mkdir -p /opt
if run_and_report_cmd "wget Rapid7Setup-Linux64.bin" wget -q -O "$OUT" "$INSIGHT_URL"; then
  if run_and_report_cmd "chmod +x Rapid7Setup-Linux64.bin" chmod +x "$OUT"; then
    LOG "OK: InsightVM installer baixado em $OUT e marcado como executável."
    LOG "Atenção: este instalador geralmente precisa ser executado manualmente (ex.: sudo $OUT) e pode requerer licença/entrada interativa."
  else
    LOG "Falha ao chmod em $OUT"
  fi
else
  LOG "Falha ao baixar InsightVM installer ($INSIGHT_URL)."
fi

# 8) Instalar Go (golang-go) se ausente (necessário para nuclei/httpx)
if command -v go >/dev/null 2>&1; then
  LOG "Go detectado: $(go version)"
else
  LOG "Go não detectado. Tentando instalar golang-go via apt (versão do repositório)."
  if try_pkg_install golang-go; then
    LOG "golang-go instalado via apt."
  else
    LOG "Falha ao instalar golang-go via apt. Se precisa de versão mais recente, instale manualmente do site oficial."
  fi
fi

# definir GOBIN para /usr/local/bin (binários globais)
export GOBIN=/usr/local/bin
mkdir -p "$GOBIN"

# 9) nuclei (ProjectDiscovery) via go install
LOG "Instalando nuclei (ProjectDiscovery) via go install..."
if command -v nuclei >/dev/null 2>&1; then
  LOG "nuclei já instalado."
else
  if command -v go >/dev/null 2>&1; then
    run_and_report_cmd "go install nuclei" /bin/bash -c "GOBIN=$GOBIN go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  else
    LOG "Go não disponível; pulei instalação de nuclei. Para instalar manualmente: sudo apt install golang-go && GOBIN=/usr/local/bin go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  fi
fi

# 10) httpx (ProjectDiscovery) via go install
LOG "Instalando httpx (ProjectDiscovery) via go install..."
if command -v httpx >/dev/null 2>&1; then
  LOG "httpx já instalado."
else
  if command -v go >/dev/null 2>&1; then
    run_and_report_cmd "go install httpx" /bin/bash -c "GOBIN=$GOBIN go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"
  else
    LOG "Go não disponível; pulei instalação de httpx."
  fi
fi

# 11) nmap
try_pkg_install nmap || true

# 12) smbclient
try_pkg_install smbclient || true

# 13) responder (apt ou clone)
LOG "Instalando Responder (repositório ou clonando do GitHub)."
if command -v responder >/dev/null 2>&1 || command -v Responder >/dev/null 2>&1; then
  LOG "Responder já presente."
else
  if try_pkg_install responder; then
    LOG "Responder instalado via apt."
  else
    LOG "Tentando clonar Responder do GitHub."
    TMP="/opt/responder-$$"
    rm -rf "$TMP"
    if run_and_report_cmd "git clone Responder" git clone https://github.com/lgandx/Responder.git "$TMP"; then
      LOG "Repositorio Responder clonado em $TMP. Execute: python3 $TMP/Responder.py"
    else
      LOG "Falha ao clonar Responder."
    fi
  fi
fi

# 14) bloodhound (collector python)
LOG "Instalando bloodhound (collector) via pip (user)."
if python3 -c "import bloodhound" >/dev/null 2>&1; then
  LOG "bloodhound-python já instalado."
else
  if $PIP_CMD install --user bloodhound; then
    LOG "bloodhound-python instalado (user)."
  else
    LOG "Falha ao instalar bloodhound-python via pip."
  fi
fi

# 15) impacket
LOG "Instalando impacket via pip (user)."
if python3 -c "import impacket" >/dev/null 2>&1; then
  LOG "impacket já instalado."
else
  if $PIP_CMD install --user impacket; then
    LOG "impacket instalado (user)."
  else
    LOG "Falha ao instalar impacket via pip."
  fi
fi

LOG "Processo concluído. Verifique as mensagens acima para ver quais instalações tiveram sucesso/erro."

LOG "Observações finais:"
LOG " - InsightVM installer foi baixado para: $OUT (chmod +x aplicado). Normalmente este instalador requer execução manual: sudo $OUT"
LOG " - Metasploit foi instalado (ou tentou instalar) usando o msfinstall (comando fornecido)."
LOG " - nuclei e httpx foram instalados via 'go install' para colocá-los em $GOBIN (/usr/local/bin). Se não apareceram no PATH, verifique /usr/local/bin."
LOG " - pipx user-installs ficam em ~/.local/bin; se pipx instalou ferramentas em user, adicione ~/.local/bin ao PATH do usuário."
LOG " - Se precisar forçar Docker + BloodHound CE via container, posso adicionar essa etapa (opcional)."

exit 0
