#!/usr/bin/env bash
# nxc-run-all-creds.sh
# Uso: sudo ./nxc-run-all-creds.sh -u <target> [-i <user>] [-p <pass>]
#
# Automatiza execuções do nxc para todos os protocolos e módulos detectados,
# opcionalmente usando credenciais fornecidas (-i usuário, -p senha).
# Salva logs em /tmp/nxc-<target>-logs-<timestamp>/ e gera um resumo heurístico.
#
set -o nounset
set +o errexit   # não sair no primeiro erro

TIMESTAMP() { date '+%Y%m%d-%H%M%S'; }
NOW=$(TIMESTAMP)
PROGNAME="$(basename "$0")"

usage() {
  cat <<EOF
$PROGNAME - roda nxc com todos os módulos contra um alvo e resume achados.

Uso:
  sudo ./$PROGNAME -u <target> [-i <usuario>] [-p <senha>]

Exemplo:
  sudo ./$PROGNAME -u 10.0.0.5 -i Administrator -p 'Senha123!'

OBS: execute apenas contra alvos autorizados.
EOF
  exit 1
}

# Parse args
TARGET=""
CRED_USER=""
CRED_PASS=""
while getopts "u:i:p:h" opt; do
  case "$opt" in
    u) TARGET="$OPTARG" ;;
    i) CRED_USER="$OPTARG" ;;
    p) CRED_PASS="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Erro: alvo (-u) obrigatório."
  usage
fi

if ! command -v nxc >/dev/null 2>&1; then
  echo "[ERROR] 'nxc' não encontrado no PATH. Instale NetExec (nxc) antes de usar este script."
  exit 2
fi

LOGDIR="/tmp/nxc-${TARGET}-logs-${NOW}"
mkdir -p "$LOGDIR"

log() { echo -e "[$(date '+%F %T')] $*"; }
log "Logs serão salvos em: $LOGDIR"
log "Iniciando varredura nxc contra: $TARGET"

# opções padrão do nxc (ajuste conforme necessário)
NXC_BASE_OPTS=(--no-progress --timeout 10 -t 8)

# combinações de flags de credenciais a testar (pares: userflag passflag)
CRED_FLAG_PAIRS=(
  "--username --password"
  "--user --pass"
  "-u -p"
  "-U -P"
)

# mascara senha para logs
mask_pass() {
  local p="$1"
  if [ -z "$p" ]; then
    echo ""
    return
  fi
  # mostra só 1 char + **** + último char se maior que 2
  local len=${#p}
  if [ "$len" -le 2 ]; then
    echo "****"
  else
    echo "${p:0:1}****${p: -1}"
  fi
}

# função que tenta executar nxc com credenciais, testando flag-pairs em sequência
# args: label outpath_and_command...
# returns: 0 se encontrou uma combinação que retornou 0, else non-zero
attempt_nxc_with_creds() {
  local label="$1"; shift
  local outpath="$1"; shift
  local -a cmd=( "$@" )  # base command elements (proto target and base opts)
  local tmpout

  # se não há credenciais, executar apenas uma vez sem cred
  if [ -z "$CRED_USER" ] || [ -z "$CRED_PASS" ]; then
    log "Executando sem credenciais: $label"
    if nxc "${cmd[@]}" > "$outpath" 2>&1; then
      log "OK: $label -> $outpath"
      return 0
    else
      log "ERRO/retorno-não-zero: $label -> $outpath"
      return 1
    fi
  fi

  # com credenciais: testar pares
  local pair
  for pair in "${CRED_FLAG_PAIRS[@]}"; do
    set -- $pair
    local userflag="$1"; shift
    local passflag="$1"
    tmpout="${outpath}.${userflag//-/}_${passflag//-/}.try"

    # montar comando com flags
    # nota: não registramos a senha nos logs
    log "Tentando $label com credenciais (usuário=${CRED_USER}, formato='${userflag} ${passflag}')"
    # construir array com inserção dos flags no final
    local -a trial_cmd=( "${cmd[@]}" "$userflag" "$CRED_USER" "$passflag" "$CRED_PASS" )
    # executar
    if nxc "${trial_cmd[@]}" > "$tmpout" 2>&1; then
      # sucesso com essa forma de credencial -> mover tmp para outpath e retornar 0
      mv -f "$tmpout" "$outpath"
      log "OK (cred): $label -> $outpath (formato ${userflag} ${passflag})"
      return 0
    else
      # falhou: manter arquivo para debug e tentar próxima forma
      mv -f "$tmpout" "${tmpout}.failed" 2>/dev/null || true
      log "Tentativa com formato (${userflag} ${passflag}) falhou (ver ${tmpout}.failed)"
    fi
  done

  # se chegou aqui, nenhuma forma funcionou: tentar sem credenciais (última tentativa)
  log "Nenhuma forma de credenciais funcionou para $label; tentando sem credenciais..."
  if nxc "${cmd[@]}" > "$outpath" 2>&1; then
    log "OK (sem cred): $label -> $outpath"
    return 0
  else
    log "ERRO/retorno-não-zero (sem cred): $label -> $outpath"
    return 1
  fi
}

# função wrapper para rodar e agregar (usa attempt_nxc_with_creds)
run_nxc() {
  local label="$1"; shift
  # safe filename
  local safe_label
  safe_label="$(echo "$label" | tr ' /' '__' | tr -c 'A-Za-z0-9_.-' '_')"
  local out="$LOGDIR/${safe_label}.log"
  # montar comando
  local -a cmd=( "$@" "${NXC_BASE_OPTS[@]}" )
  attempt_nxc_with_creds "$label" "$out" "${cmd[@]}"
  # concatenar ao agregado
  {
    echo "========== [$label] =========="
    sed -n '1,4000p' "$out" 2>/dev/null || true
    echo
    echo
  } >> "$LOGDIR/aggregate.txt"
}

# obter protocolos via nxc --help (heurística)
HELP_OUT=$(mktemp)
nxc --help > "$HELP_OUT" 2>&1 || true

PROTOCOLS=()
if grep -qE '\{[a-zA-Z0-9,_-]+\}' "$HELP_OUT"; then
  line=$(grep -oE '\{[a-zA-Z0-9,_-]+\}' "$HELP_OUT" | head -n1)
  line=${line#"{"}
  line=${line%"}"}
  IFS=',' read -r -a PROTOCOLS <<< "$line"
else
  fallback_protos=(smb ssh ldap ftp wmi winrm rdp vnc mssql nfs http https snmp)
  for p in "${fallback_protos[@]}"; do
    if grep -qiE "\b${p}\b" "$HELP_OUT"; then
      PROTOCOLS+=("$p")
    fi
  done
fi
rm -f "$HELP_OUT"

if [ ${#PROTOCOLS[@]} -eq 0 ]; then
  log "Nenhum protocolo detectado automaticamente. Usando lista padrão."
  PROTOCOLS=(smb ssh ldap ftp wmi winrm rdp vnc mssql nfs http https snmp)
fi
log "Protocolos detectados: ${PROTOCOLS[*]}"

# iniciar aggregate file
: > "$LOGDIR/aggregate.txt"

# executar para cada protocolo
for proto in "${PROTOCOLS[@]}"; do
  proto=$(echo "$proto" | tr -d '[:space:],')
  if [ -z "$proto" ]; then continue; fi

  # Execução básica do protocolo
  run_nxc "${proto}_basic" "${proto}" "${TARGET}"

  # listar módulos (-L) para esse protocolo
  MODLIST_TMP=$(mktemp)
  if nxc "$proto" -L > "$MODLIST_TMP" 2>&1; then
    mapfile -t MODULES < <(grep -Eo '^[[:space:]]*[a-zA-Z0-9_-]+' "$MODLIST_TMP" | sed 's/^[[:space:]]*//' | sort -u)
    if [ ${#MODULES[@]} -eq 0 ]; then
      mapfile -t MODULES < <(grep -Eo '[a-zA-Z0-9_-]+' "$MODLIST_TMP" | sort -u)
    fi
  else
    log "Falha ao listar módulos para $proto (nxc $proto -L). Pulando módulos."
    MODULES=()
  fi
  rm -f "$MODLIST_TMP"

  if [ ${#MODULES[@]} -eq 0 ]; then
    log "Nenhum módulo detectado para $proto."
    continue
  fi

  log "Executando ${#MODULES[@]} módulos para protocolo $proto..."
  for mod in "${MODULES[@]}"; do
    if [ "${#mod}" -lt 2 ]; then continue; fi
    run_nxc "${proto}_module_${mod}" "${proto}" "${TARGET}" -M "${mod}"
    sleep 0.4
  done
done

log "Execuções concluídas. Analisando resultados..."

# heurística de scoring (mesma lógica do script original)
SCOREFILE="$LOGDIR/scores.txt"
: > "$SCOREFILE"

awk -v IGNORECASE=1 '
function score(line) {
  s=0
  l = tolower(line)
  if (l ~ /pwn3d|pwned|pwn3/) s+=200
  if (l ~ /rce|remote code execution|remote exploit/) s+=150
  if (l ~ /critical/) s+=140
  if (l ~ /credential|credentials|password|passwd|hash|ntlm|cleartext/) s+=130
  if (l ~ /admin|administrator|root|system/ && l ~ /access|privilege|privesc|privilege escalation|pwn/) s+=120
  if (l ~ /unauthorized|unauthenticated|unauth/) s+=100
  if (l ~ /high severity|high/) s+=90
  if (l ~ /vulnerable|vulnerability|vuln/) s+=90
  if (l ~ /service.*exposed|exposed service/) s+=80
  if (l ~ /open port|port .* open/) s+=40
  if (l ~ /denied|failed|not permitted/) s-=50
  return s
}
{
  if (length($0) < 3) next
  s = score($0)
  if (s != 0) {
    gsub(/\t/, " ", $0)
    printf("%d\t%s\n", s, $0)
  }
}
' "$LOGDIR/aggregate.txt" | sort -nrk1,1 > "$SCOREFILE"

if [ ! -s "$SCOREFILE" ]; then
  log "Nenhum achado com pontuação alta. Fazendo busca por keywords básicas..."
  GREPFILE="$LOGDIR/basic_matches.txt"
  grep -iE 'pwn|pwn3d|rce|credential|password|admin|vulnerable|critical|exploit|unauthor|creds|privilege|privesc' "$LOGDIR/aggregate.txt" | sed '/^$/d' > "$GREPFILE" || true
  if [ -s "$GREPFILE" ]; then
    nl -ba "$GREPFILE" > "$SCOREFILE"
  fi
fi

TOPN=10
log "Top ${TOPN} achados (arquivo: $SCOREFILE):"
if [ -s "$SCOREFILE" ]; then
  head -n "$TOPN" "$SCOREFILE" | awk -F'\t' 'BEGIN { print "SCORE\tFINDING"; print "-----\t-------" } { if (NF==1) { print $0 } else { printf("%d\t%s\n",$1,$2) } }'
else
  log "Nenhum achado crítico detectado pela heurística. Verifique o log completo em: $LOGDIR/aggregate.txt"
fi

# Informações finais de segurança/uso
if [ -n "$CRED_USER" ] || [ -n "$CRED_PASS" ]; then
  masked=$(mask_pass "$CRED_PASS")
  log "Resumo credenciais usadas: user='${CRED_USER:-}' pass='${masked:-}' (senha não exibida por segurança)"
fi

log "Fim. Logs detalhados por execução em: $LOGDIR"

exit 0
