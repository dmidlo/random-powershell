function Add-MicrosoftOnlineToIETrustedSites {
    # Define the registry path for IE Trusted Sites
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoftonline.com"

    # Check if the registry path exists, if not create it
    If (-Not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Create the subkey for login.microsoftonline.com
    $subKey = Join-Path $regPath "login"
    If (-Not (Test-Path $subKey)) {
        New-Item -Path $subKey -Force | Out-Null
    }

    # Add the https protocol to the trusted zone (value 2 for Trusted Sites)
    Set-ItemProperty -Path $subKey -Name "https" -Value 2

    Write-Host "microsoftonline.com has been added to IE Trusted Sites."
}
