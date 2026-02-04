# ==============================================================================
# Script: Atualização Automática Windows 10/11 (Versão Corrigida)
# Correção: Instalação forçada no escopo AllUsers para evitar erro de Importação
# ==============================================================================

# 1. Verifica Admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "ERRO: Execute como Administrador!"
    Start-Sleep -Seconds 5
    Exit
}

# 2. Configurações de Segurança e Rede
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$moduleName = "PSWindowsUpdate"

# 3. Instalação Robusta do Módulo
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Host "Instalando módulo $moduleName..." -ForegroundColor Cyan
    
    try {
        # Garante que o gerenciador de pacotes NuGet está atualizado
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        
        # AQUI ESTÁ A CORREÇÃO: Mudamos Scope para AllUsers
        Install-Module -Name $moduleName -Force -AllowClobber -Scope AllUsers -Confirm:$false
        Write-Host "Módulo instalado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Error "Falha crítica na instalação do módulo: $_"
        Write-Host "Tentando método alternativo..."
        # Tenta CurrentUser como fallback se AllUsers falhar
        try {
             Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser -Confirm:$false
        } catch {
             Write-Error "Não foi possível baixar o módulo. Verifique sua internet."
             Read-Host "Pressione ENTER para sair"
             Exit
        }
    }
}

# 4. Importação Forçada
try {
    # Remove qualquer versão carregada incorretamente e importa a nova
    if (Get-Module $moduleName) { Remove-Module $moduleName -Force -ErrorAction SilentlyContinue }
    Import-Module $moduleName -Force
}
catch {
    Write-Error "Erro ao importar o módulo: $_"
    Read-Host "Pressione ENTER para sair"
    Exit
}

# 5. Execução do Update
Write-Host "------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Iniciando o Windows Update (Pode demorar)..." -ForegroundColor Yellow
Write-Host "------------------------------------------------------" -ForegroundColor Yellow

try {
    # Adicionamos -MicrosoftUpdate para pegar drivers e outros produtos se disponível
    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -Verbose
    
    Write-Host "------------------------------------------------------" -ForegroundColor Green
    Write-Host "CONCLUÍDO!" -ForegroundColor Green
    Write-Host "------------------------------------------------------" -ForegroundColor Green
}
catch {
    Write-Error "Erro durante o Update: $_"
}

Read-Host "Pressione ENTER para finalizar..."
