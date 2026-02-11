<#
.SYNOPSIS
    Instalacao do OCS Inventory Agent com certificado SSL da CA interna.
.DESCRIPTION
    Script auto-contido para deploy via ScreenConnect (ConnectWise).
    1. Deploya o cacert.pem (Root CA + Sub CA) no path do agent.
    2. Verifica versao instalada vs versao GitHub.
    3. Baixa e instala o OCS Agent se necessario.

    O certificado esta embutido no script para distribuicao simplificada.
.PARAMETER ForceInstall
    Forca reinstalacao mesmo se a versao ja estiver atualizada.
.PARAMETER CertOnly
    Apenas deploya o certificado, sem instalar/atualizar o agent.
.NOTES
    Execute como Administrador.
    Distribuir via ScreenConnect backstage.
#>

param(
    [switch]$ForceInstall,
    [switch]$CertOnly
)

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURACAO — altere aqui se necessario
# ============================================================
$ocsServerUrl   = "http://assets.madeiramadeira.com.br/ocsinventory"
$ocsExePath     = "$env:ProgramFiles\OCS Inventory Agent\OCSInventory.exe"
$cacertDir      = "$env:ProgramData\OCS Inventory NG\Agent"
$cacertPath     = "$cacertDir\cacert.pem"
$downloadDir    = "$env:TEMP\OCS_AutoInstall"
$ocsExtractDir  = "$downloadDir\OCS_Extracted"
$githubApi      = "https://api.github.com/repos/OCSInventory-NG/WindowsAgent/releases/latest"

# ============================================================
# CERTIFICADO CA INTERNA (Root CA + Sub CA)
# MadeiraMadeira Root CA (valido ate 2040)
# MadeiraMadeira Sub CA  (valido ate 2030)
# ============================================================
$cacertContent = @"
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
MENBLENOPU1TLVJvb3RDQSxDTj1DRFAsQ049UHVibGljJTIwS2V5JTIwU2Vydmlj
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
"@

# ============================================================
# FUNCOES AUXILIARES
# ============================================================

function Write-Log {
    # Exibe mensagem com timestamp e cor no console
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Get-OnlineVersion {
    # Consulta a API do GitHub para obter a ultima release do OCS Agent
    param([string]$Url)
    Write-Log "Consultando versao no GitHub..." "Yellow"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri $Url
}

# ============================================================
# INICIO
# ============================================================

# Verifica se esta rodando como Administrador
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "ERRO: Execute como Administrador." "Red"
    exit 1
}

Write-Log "=== OCS Inventory Agent - Install + Certificado ===" "Cyan"

# ------------------------------------------------------------
# ETAPA 1: Deploy do certificado cacert.pem
# ------------------------------------------------------------
Write-Log "--- Etapa 1: Deploy do certificado ---" "Cyan"

try {
    # Cria o diretorio do agent se nao existir (ex: instalacao nova)
    if (-not (Test-Path $cacertDir)) {
        Write-Log "Criando diretorio: $cacertDir" "Yellow"
        New-Item -ItemType Directory -Path $cacertDir -Force | Out-Null
    }

    # Faz backup do certificado anterior se existir
    if (Test-Path $cacertPath) {
        $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $backupPath = "$cacertPath.bak_$timestamp"
        Copy-Item -Path $cacertPath -Destination $backupPath -Force
        Write-Log "Backup do certificado anterior: $backupPath" "Gray"
    }

    # Escreve o novo certificado
    $cacertContent | Set-Content -Path $cacertPath -Encoding ASCII -Force
    Write-Log "Certificado deployado em: $cacertPath" "Green"

} catch {
    Write-Log "ERRO ao deployar certificado: $_" "Red"
    exit 1
}

# Se -CertOnly foi passado, para aqui
if ($CertOnly) {
    Write-Log "Modo CertOnly: certificado deployado. Encerrando." "Green"
    exit 0
}

# ------------------------------------------------------------
# ETAPA 2: Verificacao de versao do OCS Agent
# ------------------------------------------------------------
Write-Log "--- Etapa 2: Verificacao de versao ---" "Cyan"

try {
    $releaseInfo = Get-OnlineVersion $githubApi

    # Limpa o "v" da tag (ex: v2.10.0.0 -> 2.10.0.0)
    $onlineVersionStr = $releaseInfo.tag_name -replace "^v", ""

    try {
        $onlineVersion = [System.Version]$onlineVersionStr
    } catch {
        # Fallback se a tag vier em formato estranho
        $onlineVersion = [System.Version]"99.99.99.99"
    }

    $needInstall = $true

    # Verifica se o agent ja esta instalado
    if (Test-Path $ocsExePath) {
        $localFile = Get-Item $ocsExePath
        $localVersionStr = $localFile.VersionInfo.ProductVersion

        # Corrige formatos inconsistentes (virgulas, espacos)
        $localVersionClean = $localVersionStr -replace "," , "." -replace " ", ""

        try {
            $localVersion = [System.Version]$localVersionClean

            Write-Log "Versao local:  $localVersion" "Gray"
            Write-Log "Versao GitHub: $onlineVersion" "Gray"

            if ($localVersion -ge $onlineVersion -and -not $ForceInstall) {
                Write-Log "Agent ja esta na versao mais recente." "Green"
                $needInstall = $false
            } else {
                if ($ForceInstall) {
                    Write-Log "ForceInstall ativado. Reinstalando..." "Magenta"
                } else {
                    Write-Log "Atualizacao encontrada! Iniciando processo..." "Magenta"
                }
            }
        } catch {
            Write-Log "Nao foi possivel ler a versao local. Forcando reinstalacao." "Red"
        }
    } else {
        Write-Log "OCS Agent nao encontrado. Iniciando instalacao limpa." "Magenta"
    }

    # ------------------------------------------------------------
    # ETAPA 3: Download e instalacao
    # ------------------------------------------------------------
    if ($needInstall) {
        Write-Log "--- Etapa 3: Download e instalacao ---" "Cyan"

        # Prepara diretorios temporarios
        if (Test-Path -Path $downloadDir) {
            Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        New-Item -ItemType Directory -Path $ocsExtractDir | Out-Null

        # Busca o asset de download (ZIP x64 ou EXE x64)
        $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.zip" } | Select-Object -First 1
        if (-not $asset) {
            $asset = $releaseInfo.assets | Where-Object { $_.name -like "*x64.exe" } | Select-Object -First 1
        }
        if (-not $asset) { throw "Instalador x64 nao encontrado no GitHub." }

        $ocsUrl = $asset.browser_download_url
        $ocsFile = "$downloadDir\$($asset.name)"

        Write-Log "Baixando: $($asset.name)..." "Yellow"
        Invoke-WebRequest -Uri $ocsUrl -OutFile $ocsFile -UseBasicParsing

        # Extrai se for ZIP
        if ($ocsFile -like "*.zip") {
            Write-Log "Extraindo arquivo ZIP..." "Yellow"
            Expand-Archive -Path $ocsFile -DestinationPath $ocsExtractDir -Force
            $ocsInstaller = Get-ChildItem -Path $ocsExtractDir -Filter "*.exe" -Recurse |
                            Select-Object -First 1 |
                            Select-Object -ExpandProperty FullName
        } else {
            $ocsInstaller = $ocsFile
        }

        if (-not $ocsInstaller) { throw "Instalador nao encontrado apos download." }

        Write-Log "Instalando OCS Agent..." "Yellow"
        # /UPGRADE garante atualizacao suave se ja existir
        $ocsArgs = "/S /NOSPLASH /NO_START_MENU /NOW /SERVER=$ocsServerUrl /UPGRADE"

        $process = Start-Process -FilePath $ocsInstaller -ArgumentList $ocsArgs -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "Instalacao concluida com sucesso!" "Green"
        } else {
            Write-Log "Instalacao terminou com codigo: $($process.ExitCode)" "Red"
        }

        # Limpeza dos arquivos temporarios
        Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Arquivos temporarios removidos." "Gray"
    }

} catch {
    Write-Log "ERRO na instalacao: $_" "Red"
    # Limpa temporarios mesmo em caso de erro
    if (Test-Path -Path $downloadDir) {
        Remove-Item -Path $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# ------------------------------------------------------------
# ETAPA 4: Validacao final
# ------------------------------------------------------------
Write-Log "--- Etapa 4: Validacao ---" "Cyan"

$allOk = $true

# Verifica certificado
if (Test-Path $cacertPath) {
    $certSize = (Get-Item $cacertPath).Length
    Write-Log "[OK] cacert.pem presente ($certSize bytes)" "Green"
} else {
    Write-Log "[FALHA] cacert.pem NAO encontrado em $cacertPath" "Red"
    $allOk = $false
}

# Verifica agent instalado
if (Test-Path $ocsExePath) {
    $ver = (Get-Item $ocsExePath).VersionInfo.ProductVersion
    Write-Log "[OK] OCS Agent instalado (versao: $ver)" "Green"
} else {
    Write-Log "[AVISO] OCS Agent nao encontrado em $ocsExePath" "Yellow"
    if (-not $CertOnly) { $allOk = $false }
}

# Resultado final
if ($allOk) {
    Write-Log "=== Deploy concluido com sucesso! ===" "Green"
} else {
    Write-Log "=== Deploy concluido com avisos. Verifique os itens acima. ===" "Yellow"
}
