#!/bin/bash

# ==========================================
# Script de Instalação OCS Agent (Ubuntu)
# Executar como ROOT (sudo)
# ==========================================

# Parar o script se houver erro
set -e

# --- Configurações ---
OCS_SERVER="http://assets.madeiramadeira.com.br/ocsinventory"
CONF_FILE="/etc/ocsinventory/ocsinventory-agent.cfg"

# Cores para logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${2}[$(date +'%H:%M:%S')] $1${NC}"
}

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
  log "ERRO: Execute este script como root (sudo)." "$RED"
  exit 1
fi

# ---------------------------------------------------------
# 1. Atualização e Instalação do OCS
# ---------------------------------------------------------
log "--- Atualizando repositórios APT ---" "$YELLOW"
apt-get update -qq

log "--- Instalando OCS Inventory Agent ---" "$YELLOW"
# DEBIAN_FRONTEND=noninteractive impede perguntas durante a instalação
DEBIAN_FRONTEND=noninteractive apt-get install -y ocsinventory-agent

# ---------------------------------------------------------
# 2. Configuração
# ---------------------------------------------------------
log "--- Configurando OCS Agent ---" "$YELLOW"

# Cria backup da configuração original se existir
if [ -f "$CONF_FILE" ]; then
    cp "$CONF_FILE" "${CONF_FILE}.bak"
fi

# Define o servidor
echo "server=$OCS_SERVER" > "$CONF_FILE"

log "Configuração definida para: $OCS_SERVER" "$GREEN"

# ---------------------------------------------------------
# 3. Execução Imediata
# ---------------------------------------------------------
log "--- Forçando envio de inventário agora ---" "$YELLOW"

# Executa o agente e força o envio
ocsinventory-agent --force

log "Processo finalizado com sucesso!" "$GREEN"
