# ExchangeAuditModule.psm1

# ---------------------------------------
# Import Public Functions
# ---------------------------------------
Write-Verbose "Importing public functions..."
Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter "*.ps1" | ForEach-Object {
    Write-Verbose "Importing public function $($_.FullName)"
    . $_.FullName
}

# ---------------------------------------
# Import Classes
# ---------------------------------------
Write-Verbose "Importing classes..."
Get-ChildItem -Path "$PSScriptRoot\Classes" -Filter "*.ps1" | ForEach-Object {
    Write-Verbose "Importing class $($_.FullName)"
    . $_.FullName
}

# ---------------------------------------
# Import Private Functions
# ---------------------------------------
Write-Verbose "Importing private functions..."
Get-ChildItem -Path "$PSScriptRoot\Private" -Filter "*.ps1" | ForEach-Object {
    Write-Verbose "Importing private function $($_.FullName)"
    . $_.FullName
}

# ---------------------------------------
# Module Export Definitions
# ---------------------------------------
Write-Verbose "Exporting module members..."
Export-ModuleMember -Function 'Connect-RemoteExchange', 'Get-Mailboxes'

Write-Verbose "Module import completed."
