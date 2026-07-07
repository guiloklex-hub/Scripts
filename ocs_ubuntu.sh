#!/bin/bash
# ============================================================
# OCS Inventory Agent - Install + Certificado + Config + Inventario
# Alvo: Ubuntu/Debian. Executar como root (sudo).
# Espelha o comportamento do ocs.ps1 (Windows):
#   1. Deploya o cacert.crt (Root CA + Sub CA) embutido no script.
#   2. Instala o ocsinventory-agent se necessario.
#   3. Valida a config atual (server/ssl/ca) contra o alvo e corrige,
#      preservando as demais chaves do arquivo.
#   4. Forca o inventario e valida a saida para confirmar o envio.
#
# O cacert e usado apenas pela infra interna (.local). A comunicacao do
# agent com o servidor OCS e HTTP; ssl=1 fica gravado por padrao da
# MadeiraMadeira e so tem efeito real quando o server for https.
#
# Flags:
#   --cert-only     apenas deploya o certificado e encerra
#   --no-inventory  faz tudo menos forcar/validar o inventario
#
# Exit code 0 = sucesso total; !=0 = houve falha (util para deploy em massa).
# ============================================================

# --- Flags ---
CERT_ONLY=0
NO_INVENTORY=0
for arg in "$@"; do
    case "$arg" in
        --cert-only)    CERT_ONLY=1 ;;
        --no-inventory) NO_INVENTORY=1 ;;
        *) echo "Aviso: argumento desconhecido: $arg" ;;
    esac
done

# --- Configuracao (altere aqui se necessario) ---
OCS_PROTOCOL="http"
OCS_SERVER_HOST="assets.madeiramadeira.com.br/ocsinventory"
OCS_SERVER="${OCS_PROTOCOL}://${OCS_SERVER_HOST}"
OCS_SSL=1                                   # padrao MadeiraMadeira; so tem efeito com https
OCS_DIR="/etc/ocsinventory"
CONF_FILE="${OCS_DIR}/ocsinventory-agent.cfg"
CERT_DIR="${OCS_DIR}/certs"
CERT_FILE="${CERT_DIR}/cacert.crt"

# --- Cores / log ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'

OVERALL_OK=1
INV_OK=-1   # -1 = nao avaliado

log() { echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }

# ============================================================
# CERTIFICADO CA INTERNA (Root CA + Sub CA) - embutido
# MadeiraMadeira Root CA (valido ate 2040) / Sub CA (ate 2030)
# ============================================================
CACERT_CONTENT=$(cat <<'EOF'
-----BEGIN CERTIFICATE-----
MIIDHTCCAgWgAwIBAgIQL0E0j0fqhpNLO2fgP6k8UDANBgkqhkiG9w0BAQsFADAh
MR8wHQYDVQQDExZNYWRlaXJhTWFkZWlyYSBSb290IENBMB4XDTIwMDQyODE4NDg0
MVoXDTQwMDQyODE4NTg0MVowITEfMB0GA1UEAxMWTWFkZWlyYU1hZGVpcmEgUm9v
dCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALT2cD2RZKpO9b7D
G2zJA4C0v2P+TTHG817kjRJ/4HOMft+R1XXyFTyupRxeG4BzBx7/ydI5r3b/nV2G
fIE7KMAfKzEqqLf25CbxEs+x06OgtN8oGVxvMM2IMVXW47irIbX1NUaUYAvhJAL0
+DJwvK7iB/6aELCKB0dSBjDk6X4OM/uq+rcfB5SyAAyHBl7mvtsQjqMA+mXB/Yew
VlKP/Zi6zouHyGaLH0zUAQ8CNM8KS0OMQL9eWQ6YVxyr32P2YhT09JEAieyRCnoJ
e38mt4Cf1BcqbwJA7Ys+1gf0RfmVyuOnDYW8xo7sys7cDoNU49LT6/PMfq3Z/D1L
zLfR9mkCAwEAAaNRME8wCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYD
VR0OBBYEFJFVpYoS8x240ydiVfdU9+d/j+9VMBAGCSsGAQQBgjcVAQQDAgEAMA0G
CSqGSIb3DQEBCwUAA4IBAQA89NwsFPx5BrTz90v6LoI2zFz5zR11gxr+l5X6sPt3
9QtFF5way717d36/NtI2b3PdrL0KManzugZaAbC6MXeoPKOmOPmMgTCuNio/08iq
Qkiuv0cD0B8wd0XBmnXWdK0c6YGuHgqMpBX9sMLu3I2P2oeqolFt7DGvydBTZvJ7
8JZha+Gy37x47qexnO61w93mV3ITerbvGzeCs20qfYUIIZvlMthx2KZm1V5aHwgr
QkBo4C63+fB8oiiw2+/ItbievHD638SgsoW6JSDPpGWagQiO9+ghVWklwlITvM69
4VgQZYNJ1IhlkHQLH0bzwFDRzyAapT2Bckml9p8hz5jw
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIGcTCCBVmgAwIBAgITHQAAAAIO0cyU0rVU0QAAAAAAAjANBgkqhkiG9w0BAQsF
ADAhMR8wHQYDVQQDExZNYWRlaXJhTWFkZWlyYSBSb290IENBMB4XDTIwMDQyODIw
MzkwNloXDTMwMDQyODIwNDkwNlowVzEVMBMGCgmSJomT8ixkARkWBWxvY2FsMR4w
HAYKCZImiZPyLGQBGRYObWFkZWlyYW1hZGVpcmExHjAcBgNVBAMTFU1hZGVpcmFN
YWRlaXJhIFN1YiBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAN4y
kZiiShfMEL0kcZGZOl8hHbDrJXzspFx8+XInAhaXY3WCP/SpAyTbWdmDRTmLLp4h
j22gc7KX5Okun4E2ZEkL23Z6r1ZwLRMgCu7Ogqy+R7nHBi0FNeHxD+kGnj4M/tNk
5bxyoHQ3Z0IMBqewtDkb459xisWFd7d9GnvGIeyhmsfMflktPnBodHhnkIlXnXf7
bl+VJhRC1oMNZvM7GlLHIJGgWueE7ZH0zUYAWryj4n1K3y2t91fxj0Zdbi0nPwVQ
4StvW7JY7RV2HTFweF/ZpcsHvkbgEpsMioRTW4Gw/8EA4QQfnJv44TKsr/jHu/Bp
kr7ifpFFppXIPV3KrM0CAwEAAaOCA2owggNmMBAGCSsGAQQBgjcVAQQDAgEAMB0G
A1UdDgQWBBSGtCvGnlG8KCpVCa9c/yM8S4JNlzBmBgNVHSAEXzBdMFsGIiqGSIb3
FAG+QJN6g+xsgekAg5cygZdcgoILgqWfMITJy3EwNTAzBggrBgEFBQcCARYnaHR0
cDovL3BraS5tYWRlaXJhbWFkZWlyYS5sb2NhbC9jcHMudHh0MBkGCSsGAQQBgjcU
AgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8G
A1UdIwQYMBaAFJFVpYoS8x240ydiVfdU9+d/j+9VMIIBMwYDVR0fBIIBKjCCASYw
ggEioIIBHqCCARqGgcxsZGFwOi8vL0NOPU1hZGVpcmFNYWRlaXJhJTIwUm9vdCUy
MENBLENOPU1NLVJvb3RDQSxDTj1DRFAsQ049UHVibGljJTIwS2V5JTIwU2Vydmlj
ZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1tYWRlaXJhbWFkZWly
YSxEQz1sb2NhbD9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0
Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGSWh0dHA6Ly9wa2kubWFkZWlyYW1h
ZGVpcmEubG9jYWwvQ2VydEVucm9sbC9NYWRlaXJhTWFkZWlyYSUyMFJvb3QlMjBD
QS5jcmwwggE4BggrBgEFBQcBAQSCASowggEmMIHCBggrBgEFBQcwAoaBtWxkYXA6
Ly8vQ049TWFkZWlyYU1hZGVpcmElMjBSb290JTIwQ0EsQ049QUlBLENOPVB1Ymxp
YyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24s
REM9bWFkZWlyYW1hZGVpcmEsREM9bG9jYWw/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29i
amVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwXwYIKwYBBQUHMAKGU2h0
dHA6Ly9wa2kubWFkZWlyYW1hZGVpcmEubG9jYWwvQ2VydEVucm9sbC9NTS1Sb290
Q0FfTWFkZWlyYU1hZGVpcmElMjBSb290JTIwQ0EuY3J0MA0GCSqGSIb3DQEBCwUA
A4IBAQA6z71i2Nps07WGmMuB9kOlxEU8Q2MPh0WP3Wthctp9BlvCg21lo5S4HXcv
+w+4GZpfVugtiMkYD8iwsRR0fpIVqFAQHJNCF8W88F7du/5b9kYQzxkOVhV3HUiY
5TMp1e3BCNwhj+nZSGi+TzDt0WL5m83yI4CS+NSpUagLAnzKffa1hl2E9X1fnyJk
qDhRl1+ID3Mn24Cg6taHjOYvWPY/mxHfEty5fRPIoJwHMd9/FUlPwfzAUAnZAS3v
AiB1VxGQnTtQ2MAIQz0OTZELCjCIuooF6RgGepuzh4F32YhwE6yl3TVs3c10JF2j
NX+EosBnPJAaLuDtbm0bYAusIVFe
-----END CERTIFICATE-----
EOF
)

# ============================================================
# HELPERS
# ============================================================

# Le o valor de uma chave key=value do arquivo de config (ou vazio)
get_cfg() {
    local key="$1" file="$2"
    [ -f "$file" ] || { echo ""; return; }
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -1 \
        | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//; s/[[:space:]]*\$//"
}

# Define key=value preservando o resto do arquivo (substitui ou adiciona)
set_cfg() {
    local key="$1" val="$2" file="$3"
    touch "$file"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

ts() { date +%Y%m%d_%H%M%S; }

# ============================================================
# INICIO
# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    log "ERRO: execute este script como root (sudo)." "$RED"
    exit 1
fi

log "=== OCS Inventory Agent - Install + Certificado + Config + Inventario ===" "$CYAN"
log "Servidor alvo: ${OCS_SERVER} (ssl=${OCS_SSL})" "$CYAN"

# ------------------------------------------------------------
# ETAPA 1: Deploy do certificado
# ------------------------------------------------------------
log "--- Etapa 1: Deploy do certificado ---" "$CYAN"
mkdir -p "$CERT_DIR"
if [ -f "$CERT_FILE" ]; then
    cp -f "$CERT_FILE" "${CERT_FILE}.bak_$(ts)"
    log "Backup do certificado anterior criado." "$GRAY"
fi
printf '%s\n' "$CACERT_CONTENT" > "$CERT_FILE"
chmod 644 "$CERT_FILE"
log "Certificado deployado em: $CERT_FILE" "$GREEN"

if [ "$CERT_ONLY" -eq 1 ]; then
    log "Modo --cert-only: certificado deployado. Encerrando." "$GREEN"
    exit 0
fi

# ------------------------------------------------------------
# ETAPA 2: Instalacao do agent
# ------------------------------------------------------------
log "--- Etapa 2: Instalacao do agent ---" "$CYAN"
if command -v ocsinventory-agent >/dev/null 2>&1; then
    VER=$(dpkg-query -W -f='${Version}' ocsinventory-agent 2>/dev/null)
    log "Agent ja instalado (versao: ${VER:-desconhecida})." "$GREEN"
else
    log "Agent nao encontrado. Instalando via apt..." "$YELLOW"
    apt-get update -qq
    if DEBIAN_FRONTEND=noninteractive apt-get install -y ocsinventory-agent; then
        log "Agent instalado com sucesso." "$GREEN"
    else
        log "[FALHA] Nao foi possivel instalar o ocsinventory-agent." "$RED"
        OVERALL_OK=0
    fi
fi

# ------------------------------------------------------------
# ETAPA 3: Validacao e correcao da configuracao
# ------------------------------------------------------------
log "--- Etapa 3: Validacao da configuracao ---" "$CYAN"
mkdir -p "$OCS_DIR"

CUR_SERVER=$(get_cfg server "$CONF_FILE")
CUR_SSL=$(get_cfg ssl "$CONF_FILE")
CUR_CA=$(get_cfg ca "$CONF_FILE")

log "Config atual   -> server='${CUR_SERVER}' ssl='${CUR_SSL}' ca='${CUR_CA}'" "$GRAY"
log "Config desejada -> server='${OCS_SERVER}' ssl='${OCS_SSL}' ca='${CERT_FILE}'" "$GRAY"

if [ "$CUR_SERVER" != "$OCS_SERVER" ] || [ "$CUR_SSL" != "$OCS_SSL" ] || [ "$CUR_CA" != "$CERT_FILE" ]; then
    [ -f "$CONF_FILE" ] && cp -f "$CONF_FILE" "${CONF_FILE}.bak_$(ts)"
    set_cfg server "$OCS_SERVER" "$CONF_FILE"
    set_cfg ssl "$OCS_SSL" "$CONF_FILE"
    set_cfg ca "$CERT_FILE" "$CONF_FILE"
    log "[OK] Configuracao corrigida (backup do anterior criado)." "$GREEN"
else
    log "[OK] Configuracao ja bate com o alvo." "$GREEN"
fi

# ------------------------------------------------------------
# ETAPA 4: Forcar inventario e validar
# ------------------------------------------------------------
if [ "$NO_INVENTORY" -eq 1 ]; then
    log "--- Etapa 4: pulada (--no-inventory) ---" "$YELLOW"
elif ! command -v ocsinventory-agent >/dev/null 2>&1; then
    log "--- Etapa 4: agent nao instalado, inventario nao pode ser forcado ---" "$YELLOW"
    OVERALL_OK=0
else
    log "--- Etapa 4: Forcando inventario e validando ---" "$CYAN"
    log "Executando: ocsinventory-agent --force --debug" "$YELLOW"

    INV_OUT=$(ocsinventory-agent --force --debug 2>&1)
    INV_RC=$?
    log "ocsinventory-agent encerrou com codigo: $INV_RC" "$GRAY"

    # Marcadores de erro criticos do agent Perl (loga com prefixo [error]) e da
    # camada de rede/TLS. "failed to write ... state" e aviso benigno e e excluido.
    ERR_LINES=$(printf '%s\n' "$INV_OUT" \
        | grep -iE '\[error\]|connection refused|cannot connect|unable to connect|network is unreachable|no route to host|could not connect|timed out|timeout|ssl.*(error|fail)|handshake|http.*(4[0-9][0-9]|5[0-9][0-9])' \
        | grep -viE 'failed to (write|save).*(state|last_state)')

    if [ "$INV_RC" -eq 0 ] && [ -z "$ERR_LINES" ]; then
        log "[OK] Inventario enviado com sucesso (rc=0, sem erros no log)." "$GREEN"
        INV_OK=1
    else
        log "[FALHA] Nao foi possivel confirmar o envio do inventario (rc=$INV_RC)." "$RED"
        if [ -n "$ERR_LINES" ]; then
            log "Erros detectados:" "$RED"
            printf '%s\n' "$ERR_LINES" | while IFS= read -r l; do log "  > $l" "$RED"; done
        fi
        log "Ultimas linhas da saida do agent:" "$GRAY"
        printf '%s\n' "$INV_OUT" | tail -n 15 | while IFS= read -r l; do log "  | $l" "$GRAY"; done
        INV_OK=0
        OVERALL_OK=0
    fi
fi

# ------------------------------------------------------------
# ETAPA 5: Resumo
# ------------------------------------------------------------
log "--- Etapa 5: Resumo ---" "$CYAN"

if [ -f "$CERT_FILE" ]; then
    log "[OK] Certificado presente ($(wc -c < "$CERT_FILE") bytes)" "$GREEN"
else
    log "[FALHA] Certificado ausente em $CERT_FILE" "$RED"
    OVERALL_OK=0
fi

if command -v ocsinventory-agent >/dev/null 2>&1; then
    log "[OK] Agent instalado (versao: $(dpkg-query -W -f='${Version}' ocsinventory-agent 2>/dev/null))" "$GREEN"
else
    log "[AVISO] ocsinventory-agent nao instalado" "$YELLOW"
    OVERALL_OK=0
fi

if [ "$INV_OK" -eq 1 ]; then
    log "[OK] Inventario enviado e confirmado." "$GREEN"
elif [ "$INV_OK" -eq 0 ]; then
    log "[FALHA] Inventario nao confirmado - verifique conectividade com o servidor." "$RED"
fi

if [ "$OVERALL_OK" -eq 1 ]; then
    log "=== Deploy concluido com SUCESSO! ===" "$GREEN"
    exit 0
else
    log "=== Deploy concluido com FALHAS. Verifique os itens acima. ===" "$RED"
    exit 1
fi
