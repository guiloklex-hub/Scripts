<#
.SYNOPSIS
    Instalação/Atualização do OCS Inventory Agent + Configuração de Certificado.
.DESCRIPTION
    1. Verifica versão instalada vs versão GitHub.
    2. Baixa e instala apenas se necessário (Upgrade ou Nova Instalação).
    3. Cria/Atualiza o arquivo cacert.pem no diretório do agente.
.NOTES
    Execute como Administrador.
#>

$ErrorActionPreference = "Stop"
$downloadDir = "$env:TEMP\AutoInstall"
$ocsExtractDir = "$downloadDir\OCS_Extracted"
$ocsServerUrl = "http://assets.madeiramadeira.com.br/ocsinventory"
# Caminho padrão de instalação do OCS (x64)
$ocsExePath = "$env:ProgramFiles\OCS Inventory Agent\OCSInventory.exe"
# Caminho de dados do Agente (onde fica o cacert.pem)
$ocsDataDir = "C:\ProgramData\OCS Inventory NG\Agent"

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

    # 5. Configuração do Arquivo cacert.pem (Executa sempre para garantir que o arquivo exista)
    Write-Log "--- Verificando Certificado (cacert.pem) ---" "Cyan"

    # Conteúdo do certificado (Embutido para não depender de link externo)
    $certContent = @"
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
"@

    if (Test-Path $ocsDataDir) {
        $certPath = "$ocsDataDir\cacert.pem"
        try {
            Set-Content -Path $certPath -Value $certContent -Encoding Ascii -Force
            Write-Log "Arquivo salvo em: $certPath" "Green"
        } catch {
            Write-Log "Erro ao salvar cacert.pem: $_" "Red"
        }
    } else {
        Write-Log "AVISO: Diretório '$ocsDataDir' não encontrado." "Yellow"
        Write-Log "O Agente pode não ter sido instalado corretamente." "Yellow"
    }

} catch {
    Write-Log "Erro Crítico: $_" "Red"
}
