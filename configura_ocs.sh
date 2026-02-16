#!/bin/bash

# 1. Verifica se o script está sendo executado como root (necessário para gravar em /etc/)
if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Por favor, execute este script como root (usando sudo)."
  exit 1
fi

# Variáveis
DIR_CERTS="/etc/ocsinventory/certs"
ARQUIVO_CERT="$DIR_CERTS/cacert.crt"
URL_CERT="https://raw.githubusercontent.com/guiloklex-hub/Scripts/refs/heads/main/cacert.crt"

ARQUIVO_CFG="/etc/ocsinventory/ocsinventory-agent.cfg"
URL_CFG="https://raw.githubusercontent.com/guiloklex-hub/Scripts/refs/heads/main/ocsinventory-agent.cfg"

echo "=========================================="
echo " Configuração do Agente OCS Inventory"
echo "=========================================="

# 2. Cria a pasta de certificados (o parâmetro -p cria apenas se não existir)
echo "[1/3] Criando a pasta $DIR_CERTS..."
mkdir -p "$DIR_CERTS"

# 3. Baixa o certificado para a pasta usando wget
echo "[2/3] Baixando o certificado cacert.crt..."
wget -q -O "$ARQUIVO_CERT" "$URL_CERT"

if [ $? -eq 0 ]; then
    echo "      -> Certificado baixado com sucesso!"
else
    echo "      -> ERRO ao baixar o certificado. Verifique a conexão com a internet ou o link."
    exit 1
fi

# 4. Baixa e atualiza o arquivo de configuração do agente usando wget
echo "[3/3] Atualizando o arquivo de configuração ocsinventory-agent.cfg..."
wget -q -O "$ARQUIVO_CFG" "$URL_CFG"

if [ $? -eq 0 ]; then
    echo "      -> Configuração atualizada com sucesso!"
else
    echo "      -> ERRO ao atualizar a configuração."
    exit 1
fi

# Ajusta as permissões de leitura (boas práticas de segurança)
chmod 644 "$ARQUIVO_CERT"
chmod 644 "$ARQUIVO_CFG"

echo "=========================================="
echo " Processo concluído com sucesso!"
echo " Você já pode testar o agente com: ocsinventory-agent --debug"
echo "=========================================="

exit 0
