# ==============================================================================
# Script: Atualização Automática Windows 10/11 - Versão 3 (Blindada)
# Correção: Reinicia serviços do Windows e registra o Gerenciador de Serviço
# para corrigir erro de "Referência de objeto nula".
# ==============================================================================

# 1. Verificação de Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "ERRO: Por favor, execute como Administrador!"
    Start-Sleep -Seconds 5
    Exit
}

# 2. Configurações Iniciais
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 3. Importação do Módulo (Com verificação de segurança)
$moduleName = "PSWindowsUpdate"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Host "Instalando módulo $moduleName..." -ForegroundColor Cyan
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Install-Module -Name $moduleName -Force -AllowClobber -Scope AllUsers -Confirm:$false
    } catch {
        Write-Error "Erro crítico na instalação. Verifique sua internet."
        Exit
    }
}

# Remove versões carregadas e importa limpo
Remove-Module $moduleName -ErrorAction SilentlyContinue
Import-Module $moduleName -Force

# ==============================================================================
# CORREÇÃO DO ERRO "REFERÊNCIA DE OBJETO"
# ==============================================================================

Write-Host "Preparando ambiente do Windows Update..." -ForegroundColor Cyan

# Passo A: Reiniciar o serviço do Windows Update para destravar o agente
try {
    Write-Host "Reiniciando serviço wuauserv..." -NoNewline
    Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Warning " Não foi possível reiniciar o serviço (pode já estar parado)."
}

# Passo B: Registrar explicitamente o 'Microsoft Update' para evitar objeto nulo
# O ID abaixo é o padrão universal da Microsoft
try {
    Write-Host "Registrando Serviço de Atualização..." -NoNewline
    Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host " OK" -ForegroundColor Green
} catch {
    # Ignora erro se já estiver registrado
}

# ==============================================================================
# EXECUÇÃO DA ATUALIZAÇÃO
# ==============================================================================

Write-Host "------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Buscando e Instalando Atualizações..." -ForegroundColor Yellow
Write-Host "NÃO FECHE ESTA JANELA." -ForegroundColor Yellow
Write-Host "------------------------------------------------------" -ForegroundColor Yellow

try {
    # Usamos Install-WindowsUpdate que é um alias mais direto para -Install
    # Adicionado -MicrosoftUpdate para garantir que busque no local registrado acima
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose
    
    Write-Host "------------------------------------------------------" -ForegroundColor Green
    Write-Host "PROCESSO FINALIZADO COM SUCESSO!" -ForegroundColor Green
    Write-Host "------------------------------------------------------" -ForegroundColor Green
}
catch {
    Write-Error "Ainda ocorreu um erro: $_"
    Write-Host "Dica: Se o erro persistir, reinicie o computador manualmente e tente de novo." -ForegroundColor Gray
}

Read-Host "Pressione ENTER para sair..."
