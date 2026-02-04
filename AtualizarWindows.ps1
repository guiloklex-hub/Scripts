# ==============================================================================
# Script: Atualização Automática Windows 10/11
# Função: Instala o módulo PSWindowsUpdate, busca e aplica todas as atualizações.
# ==============================================================================

# 1. Verifica se o script está rodando como Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script precisa ser executado como Administrador!"
    Write-Warning "Por favor, clique com o botão direito e selecione 'Executar como Administrador'."
    Start-Sleep -Seconds 5
    Exit
}

# 2. Configura a política de execução apenas para esta sessão (para evitar erros de permissão)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# 3. Verifica e instala o módulo PSWindowsUpdate se necessário
$moduleName = "PSWindowsUpdate"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Host "O módulo $moduleName não foi encontrado. Instalando agora..." -ForegroundColor Cyan
    
    # Força o uso do protocolo TLS 1.2 (necessário para downloads no PowerShell antigo)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser
        Write-Host "Módulo instalado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Error "Falha ao instalar o módulo. Verifique sua conexão com a internet."
        Exit
    }
}

# 4. Importa o módulo
Import-Module $moduleName

# 5. Inicia o processo de busca e instalação
Write-Host "------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Iniciando busca por atualizações do Windows..." -ForegroundColor Yellow
Write-Host "Isso pode levar alguns minutos. Por favor, aguarde." -ForegroundColor Yellow
Write-Host "------------------------------------------------------" -ForegroundColor Yellow

# Comando principal:
# -Install: Instala as atualizações encontradas
# -AcceptAll: Aceita todos os contratos de licença automaticamente
# -IgnoreReboot: Não reinicia sozinho (segurança para o usuário salvar trabalhos)
# -Verbose: Mostra o que está acontecendo na tela

try {
    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -Verbose
    
    Write-Host "------------------------------------------------------" -ForegroundColor Green
    Write-Host "Processo finalizado!" -ForegroundColor Green
    Write-Host "Verifique acima se alguma atualização requer reinicialização." -ForegroundColor White
    Write-Host "------------------------------------------------------" -ForegroundColor Green
}
catch {
    Write-Error "Ocorreu um erro durante a atualização: $_"
}

# Pausa para ler o resultado antes de fechar a janela
Read-Host "Pressione ENTER para sair..."
