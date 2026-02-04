<#
.SYNOPSIS
    Instalação/Atualização do OCS Inventory Agent.
.DESCRIPTION
    1. Verifica versão instalada vs versão GitHub.
    2. Baixa e instala apenas se necessário (Upgrade ou Nova Instalação).
    3. Remove 7-Zip do fluxo.
.NOTES
    Execute como Administrador.
#>

$ErrorActionPreference = "Stop"
$downloadDir = "$env:TEMP\AutoInstall"
$ocsExtractDir = "$downloadDir\OCS_Extracted"
$ocsServerUrl = "http://assets.madeiramadeira.com.br/ocsinventory"
# Caminho padrão de instalação do OCS (x64)
$ocsExePath = "$env:ProgramFiles\OCS Inventory Agent\OCSInventory.exe"

# --- Funções Auxiliares ---
function Write-Log {
    param([string]$Message, [string]$Color="White")
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Get-OnlineVersion {
    param([string]$Url)
    Write-Log "Consultando GitHub..." "Yellow"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri $Url
}

# --- Início ---

# 1. Verifica Admin
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "ERRO: Execute como Administrador." "Red"; Break
}

try {
    Write-Log "--- Verificação de Versão OCS ---" "Cyan"

    # 2. Obtém informações do GitHub
    $releaseInfo = Get-OnlineVersion "https://api.github.com/repos/OCSInventory-NG/WindowsAgent/releases/latest"
    
    # Limpa o "v" da tag (ex: v2.10.0.0 -> 2.10.0.0) para comparação
    $onlineVersionStr = $releaseInfo.tag_name -replace "^v",""
    
    try {
        $onlineVersion = [System.Version]$onlineVersionStr
    } catch {
        # Fallback se a tag vier em formato estranho, assume que precisa instalar
        $onlineVersion = [System.Version]"99.99.99.99"
    }

    $needInstall = $true

    # 3. Verifica Instalação Local
    if (Test-Path $ocsExePath) {
        $localFile = Get-Item $ocsExePath
        $localVersionStr = $localFile.VersionInfo.ProductVersion
        
        # Correção: As vezes o OCS retorna versão com vírgulas ou espaços
        $localVersionClean = $localVersionStr -replace ",","." -replace " ",""
        
        try {
            $localVersion = [System.Version]$localVersionClean
            
            Write-Log "Versão Local:  $localVersion" "Gray"
            Write-Log "Versão GitHub: $onlineVersion" "Gray"

            if ($localVersion -ge $onlineVersion) {
                Write-Log "O sistema já possui a versão mais recente." "Green"
                $needInstall = $false
            } else {
                Write-Log "Atualização encontrada! Iniciando processo..." "Magenta"
            }
        } catch {
            Write-Log "Não foi possível ler a versão local corretamente. Forçando reinstalação." "Red"
        }
    } else {
        Write-Log "OCS Agent não encontrado. Iniciando instalação limpa." "Magenta"
    }

    # 4. Processo de Instalação (Só roda se $needInstall for true)
    if ($needInstall) {
        
        # Prepara diretórios
        if (Test-Path -Path $downloadDir) { Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        New-Item -ItemType Directory -Path $ocsExtractDir | Out-Null

        # Busca Asset (ZIP ou EXE)
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.zip" } | Select-Object -First 1
        if (-not $asset) {
            $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.exe" } | Select-Object -First 1
        }
        if (-not $asset) { throw "Instalador não encontrado no GitHub." }

        $ocsUrl = $asset.browser_download_url
        $ocsFile = "$downloadDir\$($asset.name)"

        Write-Log "Baixando: $($asset.name)..." "Yellow"
        Invoke-WebRequest -Uri $ocsUrl -OutFile $ocsFile

        # Extração (Se ZIP)
        if ($ocsFile -like "*.zip") {
            Write-Log "Extraindo..." "Yellow"
            Expand-Archive -Path $ocsFile -DestinationPath $ocsExtractDir -Force
            $ocsInstaller = Get-ChildItem -Path $ocsExtractDir -Filter "*.exe" -Recurse | Select-Object -First 1 | Select-Object -ExpandProperty FullName
        } else {
            $ocsInstaller = $ocsFile
        }

        if (-not $ocsInstaller) { throw "Instalador não encontrado após download." }

        Write-Log "Instalando..." "Yellow"
        # /Upgrade garante atualização suave se já existir
        $ocsArgs = "/S /NOSPLASH /NO_START_MENU /NOW /SERVER=$ocsServerUrl /UPGRADE"
        
        $process = Start-Process -FilePath $ocsInstaller -ArgumentList $ocsArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Instalação/Atualização concluída com sucesso!" "Green"
        } else {
            Write-Log "A instalação terminou com código: $($process.ExitCode)" "Red"
        }

        # Limpeza
        Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }

} catch {
    Write-Log "Erro Crítico: $_" "Red"
}
