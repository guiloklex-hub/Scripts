<#
.SYNOPSIS
    Script de instalação automatizada do 7-Zip e OCS Inventory Agent (Com suporte a ZIP).
.NOTES
    Execute como Administrador.
#>

# --- Configurações Iniciais ---
$ErrorActionPreference = "Stop"
$downloadDir = "$env:TEMP\AutoInstall"
$ocsExtractDir = "$downloadDir\OCS_Extracted"
$ocsServerUrl = "http://assets.madeiramadeira.com.br/ocsinventory"

# Limpa/Cria diretórios temporários
if (Test-Path -Path $downloadDir) { Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $downloadDir | Out-Null
New-Item -ItemType Directory -Path $ocsExtractDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Color="White")
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

# Verifica privilégios de Administrador
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "ERRO: Este script precisa ser executado como Administrador." "Red"
    Break
}

# ---------------------------------------------------------
# 1. Instalação do 7-Zip
# ---------------------------------------------------------
try {
    Write-Log "--- Iniciando processo do 7-Zip ---" "Cyan"
    
    Write-Log "Buscando a versão mais recente do 7-Zip..." "Yellow"
    $webRequest = Invoke-WebRequest -Uri "https://www.7-zip.org/" -UseBasicParsing
    
    $downloadLinkRelative = $webRequest.Links | Where-Object { $_.href -like "*-x64.exe" } | Select-Object -ExpandProperty href -First 1
    
    if (-not $downloadLinkRelative) { throw "Link do 7-Zip não encontrado." }

    $sevenZipUrl = "https://www.7-zip.org/$downloadLinkRelative"
    $sevenZipInstaller = "$downloadDir\7zip_installer.exe"

    Write-Log "Baixando 7-Zip..." "Yellow"
    Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZipInstaller

    Write-Log "Instalando 7-Zip..." "Yellow"
    Start-Process -FilePath $sevenZipInstaller -ArgumentList "/S" -Wait -PassThru | Out-Null
    Write-Log "7-Zip instalado com sucesso!" "Green"

} catch {
    Write-Log "Erro ao instalar 7-Zip: $_" "Red"
}

# ---------------------------------------------------------
# 2. Instalação do OCS Inventory Agent (Correção ZIP)
# ---------------------------------------------------------
try {
    Write-Log "`n--- Iniciando processo do OCS Inventory Agent ---" "Cyan"

    $githubApiUrl = "https://api.github.com/repos/OCSInventory-NG/WindowsAgent/releases/latest"
    
    Write-Log "Consultando GitHub (Última Release)..." "Yellow"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $releaseInfo = Invoke-RestMethod -Uri $githubApiUrl
    
    # --- CORREÇÃO AQUI: Procura por .zip ao invés de .exe ---
    $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.zip" } | Select-Object -First 1

    if (-not $asset) {
        # Tenta fallback para .exe caso voltem a usar no futuro
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.exe" } | Select-Object -First 1
    }

    if (-not $asset) { throw "Não foi possível encontrar o instalador (ZIP ou EXE) no GitHub." }

    $ocsUrl = $asset.browser_download_url
    $ocsFile = "$downloadDir\$($asset.name)"

    Write-Log "Baixando OCS Agent ($($asset.name))..." "Yellow"
    Invoke-WebRequest -Uri $ocsUrl -OutFile $ocsFile

    # Lógica de Extração se for ZIP
    if ($ocsFile -like "*.zip") {
        Write-Log "Extraindo arquivo ZIP..." "Yellow"
        Expand-Archive -Path $ocsFile -DestinationPath $ocsExtractDir -Force
        
        # Encontra o executável dentro da pasta extraída
        $ocsInstaller = Get-ChildItem -Path $ocsExtractDir -Filter "*.exe" -Recurse | Select-Object -First 1 | Select-Object -ExpandProperty FullName
    } else {
        $ocsInstaller = $ocsFile
    }

    if (-not $ocsInstaller) { throw "Executável de instalação não encontrado após extração." }

    Write-Log "Instalando OCS Agent..." "Yellow"
    
    # Flags: /S (Silent), /NOW (Força envio), /SERVER (URL)
    $ocsArgs = "/S /NOSPLASH /NO_START_MENU /NOW /SERVER=$ocsServerUrl"

    Start-Process -FilePath $ocsInstaller -ArgumentList $ocsArgs -Wait -PassThru | Out-Null

    Write-Log "OCS Inventory Agent instalado e inventário forçado (/NOW)!" "Green"

} catch {
    Write-Log "Erro ao instalar OCS Agent: $_" "Red"
}

# ---------------------------------------------------------
# Limpeza
# ---------------------------------------------------------
Write-Log "`n--- Limpeza ---" "Cyan"
if (Test-Path $downloadDir) {
    Remove-Item -Path $downloadDir -Recurse -Force
    Write-Log "Arquivos temporários removidos." "Gray"
}

Write-Log "Processo finalizado." "Green"
