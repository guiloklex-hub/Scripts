<#
.SYNOPSIS
    Instalacao + hardening do OCS Inventory Agent com certificado SSL da CA interna.
.DESCRIPTION
    Script auto-contido para deploy via ScreenConnect (ConnectWise).
    1. Deploya o cacert.pem (Root CA + Sub CA) no path do agent.
    2. Verifica versao instalada vs versao GitHub e instala/atualiza se necessario
       (com SSL habilitado, apontando para o servidor HTTPS interno).
    3. Valida a configuracao ATUAL do agent no registro (Server/SSL) contra o
       alvo desejado e corrige divergencias (ex.: maquinas antigas em HTTP).
    4. Forca a execucao imediata do inventario, obrigando a comunicacao com o
       servidor, e valida o log (OCSInventory.log) para confirmar o envio.

    O certificado esta embutido no script para distribuicao simplificada.
.PARAMETER ForceInstall
    Forca reinstalacao mesmo se a versao ja estiver atualizada.
.PARAMETER CertOnly
    Apenas deploya o certificado, sem instalar/atualizar/validar/inventariar.
.PARAMETER NoInventory
    Executa deploy do cert, install e correcao de config, mas NAO forca o
    inventario nem valida os logs de comunicacao.
.NOTES
    Execute como Administrador.
    Distribuir via ScreenConnect backstage.
    Exit code 0 = sucesso total; !=0 = houve falha (util para RMM).
#>

param(
    [switch]$ForceInstall,
    [switch]$CertOnly,
    [switch]$NoInventory
)

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURACAO - altere aqui se necessario
# ============================================================
# Servidor de comunicacao (HTTPS + validacao de certificado via CA interna)
$ocsProtocol    = "https"
$ocsServerHost  = "assets.madeiramadeira.com.br/ocsinventory"
$ocsServerUrl   = "$ocsProtocol`://$ocsServerHost"
$ocsUseSsl      = 1   # 1 = valida certificado do servidor (exige cacert.pem)

$ocsExePath     = "$env:ProgramFiles\OCS Inventory Agent\OCSInventory.exe"
$ocsDataDir     = "$env:ProgramData\OCS Inventory NG\Agent"
$cacertDir      = $ocsDataDir
$cacertPath     = "$cacertDir\cacert.pem"
$ocsIniPath     = "$ocsDataDir\ocsinventory.ini"
$ocsLogPath     = "$ocsDataDir\OCSInventory.log"
$downloadDir    = "$env:TEMP\OCS_AutoInstall"
$ocsExtractDir  = "$downloadDir\OCS_Extracted"
$githubApi      = "https://api.github.com/repos/OCSInventory-NG/WindowsAgent/releases/latest"
$ocsServiceName = "OCS Inventory Service"

# Chaves de registro onde o agent Windows guarda a config de comunicacao
# (64-bit usa WOW6432Node; 32-bit usa o caminho nativo)
$ocsRegKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\OCS Inventory Agent\Agent",
    "HKLM:\SOFTWARE\OCS Inventory Agent\Agent"
)

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
    return Invoke-RestMethod -Uri $Url -UseBasicParsing
}

function Get-OcsRegistryKey {
    # Retorna a primeira chave de registro do agent que existir (ou $null)
    foreach ($key in $ocsRegKeys) {
        if (Test-Path $key) { return $key }
    }
    return $null
}

function Get-OcsCurrentConfig {
    # Le a config atual do agent no registro. Retorna hashtable com Server/SSL
    # (valores podem ser $null se ausentes) e a chave usada.
    param([string]$RegKey)
    $cfg = @{ RegKey = $RegKey; Server = $null; SSL = $null }
    if (-not $RegKey) { return $cfg }
    try {
        $props = Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue
        if ($null -ne $props) {
            if ($props.PSObject.Properties.Name -contains 'Server') { $cfg.Server = $props.Server }
            if ($props.PSObject.Properties.Name -contains 'SSL')    { $cfg.SSL    = [int]$props.SSL }
        }
    } catch {
        Write-Log "Aviso: falha ao ler config do registro ($RegKey): $_" "Yellow"
    }
    return $cfg
}

function Set-OcsConfig {
    # Aplica os valores desejados (Server/SSL) na chave de registro do agent.
    param([string]$RegKey)
    New-ItemProperty -Path $RegKey -Name "Server" -Value $ocsServerUrl -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegKey -Name "SSL"    -Value $ocsUseSsl   -PropertyType DWord  -Force | Out-Null
}

function Get-OcsIniConfig {
    # Le Server/SSL/CA do ocsinventory.ini (config primaria dos agents 2.x).
    # Retorna hashtable; valores $null se ausentes.
    param([string]$IniPath)
    $cfg = @{ Server = $null; SSL = $null; CA = $null; Exists = $false }
    if (-not (Test-Path $IniPath)) { return $cfg }
    $cfg.Exists = $true
    try {
        foreach ($line in (Get-Content -Path $IniPath -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*Server\s*=\s*(.*?)\s*$') { $cfg.Server = $matches[1] }
            elseif ($line -match '^\s*SSL\s*=\s*(.*?)\s*$') {
                $v = $matches[1].Trim()
                if ($v -match '^\d+$') { $cfg.SSL = [int]$v }
            }
            elseif ($line -match '^\s*CA\s*=\s*(.*?)\s*$') { $cfg.CA = $matches[1] }
        }
    } catch {
        Write-Log "Aviso: falha ao ler ${IniPath}: $_" "Yellow"
    }
    return $cfg
}

function Set-OcsIniConfig {
    # Atualiza Server/SSL/CA no ocsinventory.ini preservando o restante do
    # arquivo. Edita as chaves dentro da secao [HTTP]; se ausentes, adiciona-as.
    param([string]$IniPath)

    # Se o arquivo nao existe, cria um minimo funcional
    if (-not (Test-Path $IniPath)) {
        $skeleton = @(
            "[OCS Inventory Agent]",
            "ComProvider=ComHTTP.dll",
            "",
            "[HTTP]",
            "Server=$ocsServerUrl",
            "SSL=$ocsUseSsl",
            "CA=$cacertPath"
        )
        $skeleton | Set-Content -Path $IniPath -Encoding ASCII -Force
        return
    }

    $lines = @(Get-Content -Path $IniPath -ErrorAction SilentlyContinue)
    $out = New-Object System.Collections.Generic.List[string]
    $section = ""
    $inHttp = $false
    $setServer = $false; $setSsl = $false; $setCa = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+?)\]\s*$') {
            # Ao sair da secao [HTTP], garante que as chaves ausentes foram inseridas
            if ($inHttp) {
                if (-not $setServer) { $out.Add("Server=$ocsServerUrl"); $setServer = $true }
                if (-not $setSsl)    { $out.Add("SSL=$ocsUseSsl");       $setSsl = $true }
                if (-not $setCa)     { $out.Add("CA=$cacertPath");       $setCa = $true }
            }
            $section = $matches[1]
            $inHttp = ($section -ieq 'HTTP')
            $out.Add($line)
            continue
        }

        if ($inHttp -and $line -match '^\s*Server\s*=') { $out.Add("Server=$ocsServerUrl"); $setServer = $true; continue }
        if ($inHttp -and $line -match '^\s*SSL\s*=')    { $out.Add("SSL=$ocsUseSsl");       $setSsl = $true;    continue }
        if ($inHttp -and $line -match '^\s*CA\s*=')     { $out.Add("CA=$cacertPath");       $setCa = $true;     continue }
        $out.Add($line)
    }

    # Caso [HTTP] seja a ultima secao, fecha as chaves pendentes
    if ($inHttp) {
        if (-not $setServer) { $out.Add("Server=$ocsServerUrl"); $setServer = $true }
        if (-not $setSsl)    { $out.Add("SSL=$ocsUseSsl");       $setSsl = $true }
        if (-not $setCa)     { $out.Add("CA=$cacertPath");       $setCa = $true }
    }

    # Se nao havia secao [HTTP] em lugar nenhum, cria uma ao final
    if (-not $setServer -and -not $setSsl) {
        $out.Add("")
        $out.Add("[HTTP]")
        $out.Add("Server=$ocsServerUrl")
        $out.Add("SSL=$ocsUseSsl")
        $out.Add("CA=$cacertPath")
    }

    $out | Set-Content -Path $IniPath -Encoding ASCII -Force
}

function Restart-OcsService {
    # Reinicia o servico do agent (best-effort) para carregar a nova config.
    $svc = Get-Service | Where-Object { $_.Name -like "*OCS Inventory*" -or $_.DisplayName -like "*OCS Inventory*" } | Select-Object -First 1
    if ($svc) {
        try {
            Restart-Service -Name $svc.Name -Force -ErrorAction Stop
            Write-Log "Servico '$($svc.Name)' reiniciado." "Gray"
        } catch {
            Write-Log "Aviso: nao foi possivel reiniciar o servico '$($svc.Name)': $_" "Yellow"
        }
    } else {
        Write-Log "Aviso: servico do OCS nao encontrado (inventario sera forcado via executavel)." "Yellow"
    }
}

function Test-OcsInventoryLog {
    # Analisa as linhas novas do OCSInventory.log procurando marcadores de
    # sucesso/erro de comunicacao. Retorna $true se o envio foi confirmado.
    param([string[]]$NewLines)

    if (-not $NewLines -or $NewLines.Count -eq 0) {
        Write-Log "[FALHA] Nenhuma linha nova gerada em OCSInventory.log - inventario nao rodou." "Red"
        return $false
    }

    $text = ($NewLines -join "`n")

    # Marcadores de sucesso do agent Windows do OCS
    $okProlog    = $text -match 'Send Prolog Response'
    $okInvSent   = $text -match 'Send Inventory Response'
    $okInvGen    = $text -match 'Inventory successfully generated'

    # Marcadores de falha
    $failPatterns = @(
        'Cannot establish communication',
        'Failed to send',
        'Communication failed',
        '<ERROR>',
        'ERROR:',
        'SSL.*(fail|error|cannot)',
        'certificate.*(fail|cannot|verify)',
        'HTTP.*(4\d\d|5\d\d)',
        'timed out'
    )
    $failHits = @()
    foreach ($p in $failPatterns) {
        foreach ($line in $NewLines) {
            if ($line -match $p) { $failHits += $line.Trim() }
        }
    }
    $failHits = $failHits | Select-Object -Unique

    # Sucesso = inventario enviado e aceito pelo servidor, sem erro critico
    $success = ($okInvSent -or ($okInvGen -and $okProlog)) -and ($failHits.Count -eq 0)

    Write-Log "Analise do log de comunicacao:" "Cyan"
    Write-Log ("  Prolog respondido pelo servidor : {0}" -f $(if($okProlog){'SIM'}else{'nao'})) "Gray"
    Write-Log ("  Inventario gerado localmente     : {0}" -f $(if($okInvGen){'SIM'}else{'nao'})) "Gray"
    Write-Log ("  Inventario aceito pelo servidor  : {0}" -f $(if($okInvSent){'SIM'}else{'nao'})) "Gray"

    if ($failHits.Count -gt 0) {
        Write-Log "  Erros detectados no log:" "Red"
        foreach ($h in $failHits) { Write-Log "    > $h" "Red" }
    }

    if ($success) {
        Write-Log "[OK] Comunicacao com o servidor confirmada pelo log." "Green"
    } else {
        Write-Log "[FALHA] Nao foi possivel confirmar o envio do inventario. Ultimas linhas do log:" "Red"
        $tail = $NewLines | Select-Object -Last 15
        foreach ($l in $tail) { Write-Log "    | $l" "DarkGray" }
    }
    return $success
}

# ============================================================
# INICIO
# ============================================================

# Rastreio de resultado geral (vira exit code)
$overallOk = $true

# Verifica se esta rodando como Administrador
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "ERRO: Execute como Administrador." "Red"
    exit 1
}

Write-Log "=== OCS Inventory Agent - Install + Certificado + Config + Inventario ===" "Cyan"
Write-Log "Servidor alvo: $ocsServerUrl (SSL=$ocsUseSsl)" "Cyan"

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

        Write-Log "Instalando OCS Agent (SSL habilitado, servidor HTTPS)..." "Yellow"
        # /UPGRADE atualizacao suave; /SSL=1 valida cert; /CA aponta o bundle; /NOW roda inventario ao final
        $ocsArgs = "/S /NOSPLASH /NO_START_MENU /SERVER=$ocsServerUrl /SSL=$ocsUseSsl /CA=`"$cacertPath`" /NOW /UPGRADE"

        $process = Start-Process -FilePath $ocsInstaller -ArgumentList $ocsArgs -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Log "Instalacao concluida com sucesso!" "Green"
        } else {
            Write-Log "Instalacao terminou com codigo: $($process.ExitCode)" "Red"
            $overallOk = $false
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
# ETAPA 4: Validacao e correcao da configuracao atual (registro)
# ------------------------------------------------------------
Write-Log "--- Etapa 4: Validacao da configuracao atual ---" "Cyan"

$configChanged = $false
$configValidated = $false

# --- 4a) Fonte primaria: ocsinventory.ini (agents 2.x) ---
$ini = Get-OcsIniConfig -IniPath $ocsIniPath
if ($ini.Exists) {
    $configValidated = $true
    Write-Log "Config primaria: $ocsIniPath" "Gray"
    Write-Log ("Config atual   -> Server='{0}' SSL='{1}' CA='{2}'" -f $ini.Server, $ini.SSL, $ini.CA) "Gray"
    Write-Log ("Config desejada -> Server='{0}' SSL='{1}' CA='{2}'" -f $ocsServerUrl, $ocsUseSsl, $cacertPath) "Gray"

    $serverOk = ($ini.Server -and ($ini.Server.Trim() -ieq $ocsServerUrl))
    $sslOk    = ($null -ne $ini.SSL -and [int]$ini.SSL -eq $ocsUseSsl)
    $caOk     = ($ini.CA -and ($ini.CA.Trim() -ieq $cacertPath))

    if ($serverOk -and $sslOk -and $caOk) {
        Write-Log "[OK] ocsinventory.ini ja bate com o alvo." "Green"
    } else {
        if (-not $serverOk) { Write-Log "Divergencia no Server. Corrigindo..." "Magenta" }
        if (-not $sslOk)    { Write-Log "Divergencia no SSL. Corrigindo..." "Magenta" }
        if (-not $caOk)     { Write-Log "Divergencia no CA. Corrigindo..." "Magenta" }
        try {
            # Backup antes de alterar
            $iniBackup = "$ocsIniPath.bak_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
            Copy-Item -Path $ocsIniPath -Destination $iniBackup -Force
            Set-OcsIniConfig -IniPath $ocsIniPath
            $configChanged = $true
            Write-Log "[OK] ocsinventory.ini corrigido (backup: $iniBackup)." "Green"
        } catch {
            Write-Log "[FALHA] Nao foi possivel corrigir o ocsinventory.ini: $_" "Red"
            $overallOk = $false
        }
    }
} elseif (Test-Path $ocsExePath) {
    # Agent instalado mas sem .ini: cria um coerente com o alvo
    Write-Log "ocsinventory.ini ausente - criando com a config desejada." "Magenta"
    try {
        Set-OcsIniConfig -IniPath $ocsIniPath
        $configChanged = $true
        $configValidated = $true
        Write-Log "[OK] ocsinventory.ini criado." "Green"
    } catch {
        Write-Log "[FALHA] Nao foi possivel criar o ocsinventory.ini: $_" "Red"
        $overallOk = $false
    }
}

# --- 4b) Fallback legado: registro (agents 1.x) ---
$regKey = Get-OcsRegistryKey
if ($regKey) {
    $current = Get-OcsCurrentConfig -RegKey $regKey
    $rServerOk = ($current.Server -and ($current.Server.Trim() -ieq $ocsServerUrl))
    $rSslOk    = ($null -ne $current.SSL -and [int]$current.SSL -eq $ocsUseSsl)
    if (-not ($rServerOk -and $rSslOk)) {
        Write-Log "Config legada no registro divergente ($regKey). Corrigindo..." "Magenta"
        try {
            Set-OcsConfig -RegKey $regKey
            $configChanged = $true
            $configValidated = $true
            Write-Log "[OK] Registro legado corrigido." "Green"
        } catch {
            Write-Log "[AVISO] Falha ao corrigir registro legado: $_" "Yellow"
        }
    } else {
        $configValidated = $true
        Write-Log "[OK] Registro legado ja bate com o alvo." "Gray"
    }
}

if (-not $configValidated -and (Test-Path $ocsExePath)) {
    Write-Log "[AVISO] Nao foi possivel localizar nenhuma config (.ini/registro) do agent." "Yellow"
    $overallOk = $false
}

# ------------------------------------------------------------
# ETAPA 5: Forcar inventario e validar comunicacao pelos logs
# ------------------------------------------------------------
$inventoryOk = $null
if ($NoInventory) {
    Write-Log "--- Etapa 5: pulada (-NoInventory) ---" "Yellow"
} elseif (-not (Test-Path $ocsExePath)) {
    Write-Log "--- Etapa 5: agent nao instalado, inventario nao pode ser forcado ---" "Yellow"
    $overallOk = $false
} else {
    Write-Log "--- Etapa 5: Forcando inventario e validando comunicacao ---" "Cyan"

    # Recarrega a config se ela foi alterada
    if ($configChanged) { Restart-OcsService }

    # Captura o estado do log antes da execucao para isolar as linhas novas
    $preLines = 0
    if (Test-Path $ocsLogPath) {
        $preLines = @(Get-Content -Path $ocsLogPath -ErrorAction SilentlyContinue).Count
    }

    Write-Log "Executando OCSInventory.exe /NOW /DEBUG (forcando envio)..." "Yellow"
    try {
        # /NOW ignora frequencia; /DEBUG gera log detalhado; /SERVER garante o destino
        $invArgs = "/NOW /DEBUG /SERVER=$ocsServerUrl /SSL=$ocsUseSsl"
        $invProc = Start-Process -FilePath $ocsExePath -ArgumentList $invArgs -Wait -PassThru
        Write-Log "OCSInventory.exe encerrou com codigo: $($invProc.ExitCode)" "Gray"
    } catch {
        Write-Log "[FALHA] Erro ao executar o inventario: $_" "Red"
        $overallOk = $false
    }

    # Da um instante para o log ser flushado ao disco
    Start-Sleep -Seconds 3

    # Le apenas as linhas geradas por esta execucao
    $newLines = @()
    if (Test-Path $ocsLogPath) {
        $allLines = @(Get-Content -Path $ocsLogPath -ErrorAction SilentlyContinue)
        if ($allLines.Count -gt $preLines) {
            $newLines = $allLines[$preLines..($allLines.Count - 1)]
        } else {
            # Log foi rotacionado/truncado - analisa o conteudo inteiro
            $newLines = $allLines
        }
    } else {
        Write-Log "[FALHA] Log de inventario nao encontrado em $ocsLogPath" "Red"
    }

    $inventoryOk = Test-OcsInventoryLog -NewLines $newLines
    if (-not $inventoryOk) { $overallOk = $false }
}

# ------------------------------------------------------------
# ETAPA 6: Validacao final
# ------------------------------------------------------------
Write-Log "--- Etapa 6: Resumo ---" "Cyan"

# Verifica certificado
if (Test-Path $cacertPath) {
    $certSize = (Get-Item $cacertPath).Length
    Write-Log "[OK] cacert.pem presente ($certSize bytes)" "Green"
} else {
    Write-Log "[FALHA] cacert.pem NAO encontrado em $cacertPath" "Red"
    $overallOk = $false
}

# Verifica agent instalado
if (Test-Path $ocsExePath) {
    $ver = (Get-Item $ocsExePath).VersionInfo.ProductVersion
    Write-Log "[OK] OCS Agent instalado (versao: $ver)" "Green"
} else {
    Write-Log "[AVISO] OCS Agent nao encontrado em $ocsExePath" "Yellow"
    $overallOk = $false
}

# Status do inventario
if ($null -ne $inventoryOk) {
    if ($inventoryOk) {
        Write-Log "[OK] Inventario enviado e confirmado pelo servidor." "Green"
    } else {
        Write-Log "[FALHA] Inventario nao confirmado - verifique conectividade/HTTPS/cert." "Red"
    }
}

# Resultado final + exit code para RMM
if ($overallOk) {
    Write-Log "=== Deploy concluido com SUCESSO! ===" "Green"
    exit 0
} else {
    Write-Log "=== Deploy concluido com FALHAS. Verifique os itens acima. ===" "Red"
    exit 1
}
