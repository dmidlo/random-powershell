function Get-LocalSubnet {
    # Get the default network interface
    $interface = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "0.0.0.0" }).InterfaceAlias

    # Get the IP address and subnet mask of the default interface
    $ip_info = Get-NetIPAddress -InterfaceAlias $interface | Where-Object { $_.AddressFamily -eq 'IPv4' }

    # Convert the subnet mask to CIDR notation
    $subnet_mask = $ip_info.PrefixLength
    $ip_address = $ip_info.IPAddress

    # Combine the IP address and CIDR notation
    "$ip_address/$subnet_mask"
}

function Get-LocalCIDR {
    # Get the default network interface
    $interface = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "0.0.0.0" }).InterfaceAlias

    # Get the IP address and subnet mask of the default interface
    $ip_info = Get-NetIPAddress -InterfaceAlias $interface | Where-Object { $_.AddressFamily -eq 'IPv4' }

    # Convert the subnet mask to CIDR notation
    $subnet_mask = $ip_info.PrefixLength

    # Combine the IP address and CIDR notation
    $subnet_mask
}

function Enumerate-MacsToCSV {
    # Get the default gateway to infer the subnet
    $defaultGateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "0.0.0.0" }).NextHop
    $subnet = ($defaultGateway -replace "\.\d+$") + ".0/$(Get-LocalCIDR)"

    # Output file with a timestamp in the filename
    $outputFile = if ($args.Count -eq 0) { "mac_addresses_$((Get-Date).ToString('yyyyMMddHHmm')).csv" } else { $args[0] }

    # Header for the CSV file
    "IP Address,MAC Address,Manufacturer" | Out-File -FilePath $outputFile

    # Run nmap to scan for MAC addresses and output to CSV
    $nmapOutput = nmap -sP $subnet
    $nmapOutput -split "`r`n" | ForEach-Object {
        if ($_ -match "Nmap scan report for") {
            $ip = ($_ -split " ")[-1]
        } elseif ($_ -match "MAC Address:") {
            $mac = ($_ -split " ")[2]
            $manufacturer = ($_ -replace ".*MAC Address: [^ ]+ ", "")
            "$ip,$mac,$manufacturer" | Out-File -FilePath $outputFile -Append
        }
    }

    Write-Host "MAC addresses written to $outputFile"
}

function Compare-MacCsv {
    param (
        [string]$file1,
        [string]$file2
    )
    
    # Check if both files exist
    if (-not (Test-Path $file1) -or -not (Test-Path $file2)) {
        Write-Host "Both files must exist. Usage: Compare-MacCsv -file1 <file1.csv> -file2 <file2.csv>"
        return
    }

    # Import both CSV files, skipping the header (as done by tail in Bash)
    $csv1 = Import-Csv -Path $file1
    $csv2 = Import-Csv -Path $file2

    # Compare the two CSVs, using 'SideIndicator' to mark differences
    $differences = Compare-Object -ReferenceObject $csv1 -DifferenceObject $csv2 -Property "IP Address", "MAC Address", "Manufacturer" -PassThru

    if ($differences) {
        Write-Host "Differences between $file1 and $file2 :"
        $differences | Format-Table
    } else {
        Write-Host "No differences found between $file1 and $file2."
    }
}

# Example usage:
# Compare-MacCsv -file1 "mac_addresses_20230901.csv" -file2 "mac_addresses_20230902.csv"



