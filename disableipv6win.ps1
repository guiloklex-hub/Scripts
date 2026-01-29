# ObtÃ©m todas as interfaces onde o IPv6 (ms_tcpip6) estÃ¡ atualmente habilitado
$interfaces = Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" -and $_.Enabled -eq $true }

foreach ($adapter in $interfaces) {
    Write-Host "Desativando IPv6 na interface: $($adapter.Name)" -ForegroundColor Cyan
    
    # Executa a desativaÃ§Ã£o para o nome especÃ­fico da interface
    Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6
}

ipconfig /release ; ipconfig /renew ; ipconfig /flushdns

Write-Host "Procedimento concluÃ­do!" -ForegroundColor Green
