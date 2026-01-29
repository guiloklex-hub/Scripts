# Define o URL da ferramenta oficial do Speedtest (Ookla) para Windows
$url = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
$tempDir = "$env:TEMP\SpeedTestCLI"
$zipPath = "$tempDir\speedtest.zip"
$exePath = "$tempDir\speedtest.exe"

Write-Host "--- Iniciando ConfiguraÃ§Ã£o do Speedtest ---" -ForegroundColor Cyan

# Cria diretÃ³rio temporÃ¡rio se nÃ£o existir
if (!(Test-Path -Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Baixa a ferramenta
Write-Host "Baixando o Speedtest CLI..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
}
catch {
    Write-Error "Falha ao baixar o arquivo. Verifique sua conexÃ£o."
    break
}

# Extrai o arquivo
Write-Host "Extraindo arquivos..." -ForegroundColor Yellow
Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

# Executa o teste
if (Test-Path -Path $exePath) {
    Write-Host "--- Rodando Teste de Velocidade ---" -ForegroundColor Green
    Write-Host "Isso pode levar alguns segundos..."
    
    # O argumento --accept-license aceita os termos automaticamente para nÃ£o travar o script
    & $exePath --accept-license --accept-gdpr
    
    Write-Host "`n--- Teste Finalizado ---" -ForegroundColor Cyan
}
else {
    Write-Error "ExecutÃ¡vel nÃ£o encontrado apÃ³s extraÃ§Ã£o."
}

# Opcional: Limpeza (Remova o # da linha abaixo se quiser apagar a ferramenta apÃ³s o uso)
Remove-Item -Path $tempDir -Recurse -Force
