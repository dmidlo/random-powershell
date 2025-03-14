# Author: David Midlo - david@avartec.com
#  - This is the **Missing Piece** for windows IPAM

# BETA v0.0.1

# Quick Notes:
# Lots of work to be done, but this script provides several functions for IPv4 Address Discovery and Management
#  - It provides a Native Powershell 5 compatible network scanner (similar to nmap) So it is usable on legacy Windows Deployments.
#  - Advanced Windows Server IPAM integration to scan a subnet looking for IP addresses not already managed by IPAM
#    Adding them as static IPv4 addresses.
#
#  - Even if IPAM isn't deployed in an infrastructure, the IPv4 Scanner can still be quite useful as a standalone
#    function to enumerate active IPs without the need for installing additional software
#
#  - Alot of the packaging niceties need to be set up still (end goal being `Import-Module IPAMTools`), but still working
#    the feature set before I decide on the project's module structure.
#
#  - USAGE:
#
#  - Source the script into your current powershell session:
#
#      . .\IPAM_Tools.ps1
#
#
#         if sourcing the file on a system that doesn't have windows server IPAM installed
#         you will get an error this error is safe to ignore:
#                Get-IpamSubnet : The term 'Get-IpamSubnet' is not recognized as the name of a
#                cmdlet, function, script file, or operable program. Check the spelling of the
#                name, or if a path was included, verify that the path is correct and try again.
#                At C:\Users\David\Documents\WindowsPowerShell\IPAM_Tools.ps1:657 char:16
#                +     $subnets = Get-IpamSubnet -AddressFamily IPv4
#                +                ~~~~~~~~~~~~~~
#                    + CategoryInfo          : ObjectNotFound: (Get-IpamSubnet:String) [], Comm
#                andNotFoundException
#                    + FullyQualifiedErrorId : CommandNotFoundException
#
#  - To conduct a basic scan to see active IPs for 192.168.0.0/24 network:
#         Invoke-IPv4NetworkScanPS -IPv4Address 192.168.0.1 -CIDR 24
#
#  - Scanning a range:
#      Invoke-IPv4NetworkScan -StartIPv4Address 192.168.178.0 -EndIPv4Address 192.168.178.20
#
#  - To see which IPs Are not in IPAM (Automatically detects subnets and IPs in IPAM and conducts a live scan, outputting **ONLY** new IPv4 addresses)
#      Test-IPAMMissingActiveIPv4StaticIPs
#
#  Use `Add-IPAMMissingActiveIPv4StaticIPs`.  It does the same thing as Test... but adds the diff'ed addresses directly into IPAM as well.
#
#
#
#   The scanner portion of this code was adapted from https://github.com/BornToBeRoot/PowerShell/blob/master/Module/LazyAdmin/Functions/Network/Invoke-IPv4NetworkScan.ps1
#   more work needs to be done to fully integrate the scanner and IPAM under various use-cases.


function Invoke-IPv4NetworkScanPS {
    Param(
        [Parameter(
            ParameterSetName = 'Range',
            Position = 0,
            Mandatory = $true,
            HelpMessage = 'Start IPv4-Address like 192.168.1.10')]
        [IPAddress]$StartIPv4Address,

        [Parameter(
            ParameterSetName = 'Range',
            Position = 1,
            Mandatory = $true,
            HelpMessage = 'End IPv4-Address like 192.168.1.100')]
        [IPAddress]$EndIPv4Address,
        
        [Parameter(
            ParameterSetName = 'CIDR',
            Position = 0,
            Mandatory = $true,
            HelpMessage = 'IPv4-Address which is in the subnet')]
        [Parameter(
            ParameterSetName = 'Mask',
            
            Position = 0,
            Mandatory = $true,
            HelpMessage = 'IPv4-Address which is in the subnet')]
        [IPAddress]$IPv4Address,

        [Parameter(
            ParameterSetName = 'CIDR',        
            Position = 1,
            Mandatory = $true,
            HelpMessage = 'CIDR like /24 without "/"')]
        [ValidateRange(0, 31)]
        [Int32]$CIDR,
    
        [Parameter(
            ParameterSetName = 'Mask',
            Position = 1,
            Mandatory = $true,
            Helpmessage = 'Subnetmask like 255.255.255.0')]
        [ValidateScript({
                if ($_ -match "^(254|252|248|240|224|192|128).0.0.0$|^255.(254|252|248|240|224|192|128|0).0.0$|^255.255.(254|252|248|240|224|192|128|0).0$|^255.255.255.(254|252|248|240|224|192|128|0)$") {
                    return $true
                }
                else {
                    throw "Enter a valid subnetmask (like 255.255.255.0)!"    
                }
            })]
        [String]$Mask,

        [Parameter(
            Position = 2,
            HelpMessage = 'Maxmium number of ICMP checks for each IPv4-Address (Default=2)')]
        [Int32]$Tries = 2,

        [Parameter(
            Position = 3,
            HelpMessage = 'Maximum number of threads at the same time (Default=256)')]
        [Int32]$Threads = 256,
        
        [Parameter(
            Position = 4,
            HelpMessage = 'Resolve DNS for each IP (Default=Enabled)')]
        [Switch]$DisableDNSResolving,

        [Parameter(
            Position = 5,
            HelpMessage = 'Resolve MAC-Address for each IP (Default=Disabled)')]
        [Switch]$EnableMACResolving,

        [Parameter(
            Position = 6,
            HelpMessage = 'Get extendend informations like BufferSize, ResponseTime and TTL (Default=Disabled)')]
        [Switch]$ExtendedInformations,

        [Parameter(
            Position = 7,
            HelpMessage = 'Include inactive devices in result')]
        [Switch]$IncludeInactive
    )

    Begin {
        Write-Verbose -Message "Script started at $(Get-Date)"
        
        $OUIListPath = "$PSScriptRoot\Resources\oui.txt"

        function Convert-Subnetmask {
            [CmdLetBinding(DefaultParameterSetName = 'CIDR')]
            param( 
                [Parameter( 
                    ParameterSetName = 'CIDR',       
                    Position = 0,
                    Mandatory = $true,
                    HelpMessage = 'CIDR like /24 without "/"')]
                [ValidateRange(0, 32)]
                [Int32]$CIDR,

                [Parameter(
                    ParameterSetName = 'Mask',
                    Position = 0,
                    Mandatory = $true,
                    HelpMessage = 'Subnetmask like 255.255.255.0')]
                [ValidateScript({
                        if ($_ -match "^(254|252|248|240|224|192|128).0.0.0$|^255.(254|252|248|240|224|192|128|0).0.0$|^255.255.(254|252|248|240|224|192|128|0).0$|^255.255.255.(255|254|252|248|240|224|192|128|0)$") {
                            return $true
                        }
                        else {
                            throw "Enter a valid subnetmask (like 255.255.255.0)!"    
                        }
                    })]
                [String]$Mask
            )

            Begin {

            }

            Process {
                switch ($PSCmdlet.ParameterSetName) {
                    "CIDR" {                          
                        # Make a string of bits (24 to 11111111111111111111111100000000)
                        $CIDR_Bits = ('1' * $CIDR).PadRight(32, "0")
                        
                        # Split into groups of 8 bits, convert to Ints, join up into a string
                        $Octets = $CIDR_Bits -split '(.{8})' -ne ''
                        $Mask = ($Octets | ForEach-Object -Process { [Convert]::ToInt32($_, 2) }) -join '.'
                    }

                    "Mask" {
                        # Convert the numbers into 8 bit blocks, join them all together, count the 1
                        $Octets = $Mask.ToString().Split(".") | ForEach-Object -Process { [Convert]::ToString($_, 2) }
                        $CIDR_Bits = ($Octets -join "").TrimEnd("0")

                        # Count the "1" (111111111111111111111111 --> /24)                     
                        $CIDR = $CIDR_Bits.Length             
                    }               
                }

                [pscustomobject] @{
                    Mask = $Mask
                    CIDR = $CIDR
                }
            }

            End {
                
            }
        }

        # Helper function to convert an IPv4-Address to Int64 and vise versa
        function Convert-IPv4Address {
            [CmdletBinding(DefaultParameterSetName = 'IPv4Address')]
            param(
                [Parameter(
                    ParameterSetName = 'IPv4Address',
                    Position = 0,
                    Mandatory = $true,
                    HelpMessage = 'IPv4-Address as string like "192.168.1.1"')]
                [IPaddress]$IPv4Address,

                [Parameter(
                    ParameterSetName = 'Int64',
                    Position = 0,
                    Mandatory = $true,
                    HelpMessage = 'IPv4-Address as Int64 like 2886755428')]
                [long]$Int64
            ) 

            Begin {

            }

            Process {
                switch ($PSCmdlet.ParameterSetName) {
                    # Convert IPv4-Address as string into Int64
                    "IPv4Address" {
                        $Octets = $IPv4Address.ToString().Split(".") 
                        $Int64 = [long]([long]$Octets[0] * 16777216 + [long]$Octets[1] * 65536 + [long]$Octets[2] * 256 + [long]$Octets[3]) 
                    }
            
                    # Convert IPv4-Address as Int64 into string 
                    "Int64" {            
                        $IPv4Address = (([System.Math]::Truncate($Int64 / 16777216)).ToString() + "." + ([System.Math]::Truncate(($Int64 % 16777216) / 65536)).ToString() + "." + ([System.Math]::Truncate(($Int64 % 65536) / 256)).ToString() + "." + ([System.Math]::Truncate($Int64 % 256)).ToString())
                    }      
                }

                [pscustomobject] @{   
                    IPv4Address = $IPv4Address
                    Int64       = $Int64
                }
            }

            End {

            }
        }

        # Helper function to create a new Subnet
        function Get-IPv4Subnet {
            [CmdletBinding(DefaultParameterSetName = 'CIDR')]
            param(
                [Parameter(
                    Position = 0,
                    Mandatory = $true,
                    HelpMessage = 'IPv4-Address which is in the subnet')]
                [IPAddress]$IPv4Address,

                [Parameter(
                    ParameterSetName = 'CIDR',
                    Position = 1,
                    Mandatory = $true,
                    HelpMessage = 'CIDR like /24 without "/"')]
                [ValidateRange(0, 31)]
                [Int32]$CIDR,

                [Parameter(
                    ParameterSetName = 'Mask',
                    Position = 1,
                    Mandatory = $true,
                    Helpmessage = 'Subnetmask like 255.255.255.0')]
                [ValidateScript({
                        if ($_ -match "^(254|252|248|240|224|192|128).0.0.0$|^255.(254|252|248|240|224|192|128|0).0.0$|^255.255.(254|252|248|240|224|192|128|0).0$|^255.255.255.(254|252|248|240|224|192|128|0)$") {
                            return $true
                        }
                        else {
                            throw "Enter a valid subnetmask (like 255.255.255.0)!"    
                        }
                    })]
                [String]$Mask
            )

            Begin {
            
            }

            Process {
                # Convert Mask or CIDR - because we need both in the code below
                switch ($PSCmdlet.ParameterSetName) {
                    "CIDR" {                          
                        $Mask = (Convert-Subnetmask -CIDR $CIDR).Mask            
                    }
                    "Mask" {
                        $CIDR = (Convert-Subnetmask -Mask $Mask).CIDR          
                    }                  
                }
                
                # Get CIDR Address by parsing it into an IP-Address
                $CIDRAddress = [System.Net.IPAddress]::Parse([System.Convert]::ToUInt64(("1" * $CIDR).PadRight(32, "0"), 2))
            
                # Binary AND ... this is how subnets work.
                $NetworkID_bAND = $IPv4Address.Address -band $CIDRAddress.Address

                # Return an array of bytes. Then join them.
                $NetworkID = [System.Net.IPAddress]::Parse([System.BitConverter]::GetBytes([UInt32]$NetworkID_bAND) -join ("."))
                
                # Get HostBits based on SubnetBits (CIDR) // Hostbits (32 - /24 = 8 -> 00000000000000000000000011111111)
                $HostBits = ('1' * (32 - $CIDR)).PadLeft(32, "0")
                
                # Convert Bits to Int64
                $AvailableIPs = [Convert]::ToInt64($HostBits, 2)

                # Convert Network Address to Int64
                $NetworkID_Int64 = (Convert-IPv4Address -IPv4Address $NetworkID.ToString()).Int64

                # Convert add available IPs and parse into IPAddress
                $Broadcast = [System.Net.IPAddress]::Parse((Convert-IPv4Address -Int64 ($NetworkID_Int64 + $AvailableIPs)).IPv4Address)
                
                # Change useroutput ==> (/27 = 0..31 IPs -> AvailableIPs 32)
                $AvailableIPs += 1

                # Hosts = AvailableIPs - Network Address + Broadcast Address
                $Hosts = ($AvailableIPs - 2)
                    
                # Build custom PSObject
                [pscustomobject] @{
                    NetworkID = $NetworkID
                    Broadcast = $Broadcast
                    IPs       = $AvailableIPs
                    Hosts     = $Hosts
                }
            }

            End {

            }
        }     
    }

    Process {
        # Calculate Subnet (Start and End IPv4-Address)
        if ($PSCmdlet.ParameterSetName -eq 'CIDR' -or $PSCmdlet.ParameterSetName -eq 'Mask') {
            # Convert Subnetmask
            if ($PSCmdlet.ParameterSetName -eq 'Mask') {
                $CIDR = (Convert-Subnetmask -Mask $Mask).CIDR     
            }

            # Create new subnet
            $Subnet = Get-IPv4Subnet -IPv4Address $IPv4Address -CIDR $CIDR

            # Assign Start and End IPv4-Address
            $StartIPv4Address = $Subnet.NetworkID
            $EndIPv4Address = $Subnet.Broadcast
        }

        # Convert Start and End IPv4-Address to Int64
        $StartIPv4Address_Int64 = (Convert-IPv4Address -IPv4Address $StartIPv4Address.ToString()).Int64
        $EndIPv4Address_Int64 = (Convert-IPv4Address -IPv4Address $EndIPv4Address.ToString()).Int64

        # Check if range is valid
        if ($StartIPv4Address_Int64 -gt $EndIPv4Address_Int64) {
            Write-Error -Message "Invalid IP-Range... Check your input!" -Category InvalidArgument -ErrorAction Stop
        }

        # Calculate IPs to scan (range)
        $IPsToScan = ($EndIPv4Address_Int64 - $StartIPv4Address_Int64)
        
        Write-Verbose -Message "Scanning range from $StartIPv4Address to $EndIPv4Address ($($IPsToScan + 1) IPs)"
        Write-Verbose -Message "Running with max $Threads threads"
        Write-Verbose -Message "ICMP checks per IP: $Tries"

        # Properties which are displayed in the output
        $PropertiesToDisplay = @()
        $PropertiesToDisplay += "IPv4Address", "Status"

        if ($DisableDNSResolving -eq $false) {
            $PropertiesToDisplay += "Hostname"
        }

        if ($EnableMACResolving) {
            $PropertiesToDisplay += "MAC"
        }

        # Check if it is possible to assign vendor to MAC --> import CSV-File 
        if ($EnableMACResolving) {
            if (Test-Path -Path $OUIListPath -PathType Leaf) {
                $OUIHashTable = @{ }

                Write-Verbose -Message "Read oui.txt and fill hash table..."

                foreach ($Line in Get-Content -Path $OUIListPath) {
                    if (-not([String]::IsNullOrEmpty($Line))) {
                        try {
                            $HashTableData = $Line.Split('|')
                            $OUIHashTable.Add($HashTableData[0], $HashTableData[1])
                        }
                        catch [System.ArgumentException] { } # Catch if mac is already added to hash table
                    }
                }

                $AssignVendorToMAC = $true

                $PropertiesToDisplay += "Vendor"
            }
            else {
                $AssignVendorToMAC = $false

                Write-Warning -Message "No OUI-File to assign vendor with MAC-Address found! Execute the script ""Create-OUIListFromWeb.ps1"" to download the latest version. This warning does not affect the scanning procedure."
            }
        }  
        
        if ($ExtendedInformations) {
            $PropertiesToDisplay += "BufferSize", "ResponseTime", "TTL"
        }

        # Scriptblock --> will run in runspaces (threads)...
        [System.Management.Automation.ScriptBlock]$ScriptBlock = {
            Param(
                $IPv4Address,
                $Tries,
                $DisableDNSResolving,
                $EnableMACResolving,
                $ExtendedInformations,
                $IncludeInactive
            )
    
            # +++ Send ICMP requests +++
            $Status = [String]::Empty

            for ($i = 0; $i -lt $Tries; i++) {
                try {
                    $PingObj = New-Object System.Net.NetworkInformation.Ping
                    
                    $Timeout = 1000
                    $Buffer = New-Object Byte[] 32
                    
                    $PingResult = $PingObj.Send($IPv4Address, $Timeout, $Buffer)

                    if ($PingResult.Status -eq "Success") {
                        $Status = "Up"
                        break # Exit loop, if host is reachable
                    }
                    else {
                        $Status = "Down"
                    }
                }
                catch {
                    $Status = "Down"
                    break # Exit loop, if there is an error
                }
            }
                
            # +++ Resolve DNS +++
            $Hostname = [String]::Empty     

            if ((-not($DisableDNSResolving)) -and ($Status -eq "Up" -or $IncludeInactive)) {   	
                try { 
                    $Hostname = ([System.Net.Dns]::GetHostEntry($IPv4Address).HostName)
                } 
                catch { } # No DNS      
            }
        
            # +++ Get MAC-Address +++
            $MAC = [String]::Empty 

            if (($EnableMACResolving) -and (($Status -eq "Up") -or ($IncludeInactive))) {
                $Arp_Result = (arp -a).ToUpper().Trim()

                foreach ($Line in $Arp_Result) {                
                    if ($Line.Split(" ")[0] -eq $IPv4Address) {                    
                        $MAC = [Regex]::Matches($Line, "([0-9A-F][0-9A-F]-){5}([0-9A-F][0-9A-F])").Value
                    }
                }
            }

            # +++ Get extended informations +++
            $BufferSize = [String]::Empty 
            $ResponseTime = [String]::Empty 
            $TTL = $null

            if ($ExtendedInformations -and ($Status -eq "Up")) {
                try {
                    $BufferSize = $PingResult.Buffer.Length
                    $ResponseTime = $PingResult.RoundtripTime
                    $TTL = $PingResult.Options.Ttl
                }
                catch { } # Failed to get extended informations
            }	
        
            # +++ Result +++        
            if (($Status -eq "Up") -or ($IncludeInactive)) {
                [pscustomobject] @{
                    IPv4Address  = $IPv4Address
                    Status       = $Status
                    Hostname     = $Hostname
                    MAC          = $MAC   
                    BufferSize   = $BufferSize
                    ResponseTime = $ResponseTime
                    TTL          = $TTL
                }
            }
            else {
                $null
            }
        } 

        Write-Verbose -Message "Setting up RunspacePool..."

        # Create RunspacePool and Jobs
        $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Threads, $Host)
        $RunspacePool.Open()
        [System.Collections.ArrayList]$Jobs = @()

        Write-Verbose -Message "Setting up jobs..."

        # Set up jobs for each IP...
        for ($i = $StartIPv4Address_Int64; $i -le $EndIPv4Address_Int64; $i++) { 
            # Convert IP back from Int64
            $IPv4Address = (Convert-IPv4Address -Int64 $i).IPv4Address                

            # Create hashtable to pass parameters
            $ScriptParams = @{
                IPv4Address          = $IPv4Address
                Tries                = $Tries
                DisableDNSResolving  = $DisableDNSResolving
                EnableMACResolving   = $EnableMACResolving
                ExtendedInformations = $ExtendedInformations
                IncludeInactive      = $IncludeInactive
            }       

            # Catch when trying to divide through zero
            try {
                $Progress_Percent = (($i - $StartIPv4Address_Int64) / $IPsToScan) * 100 
            } 
            catch { 
                $Progress_Percent = 100 
            }

            Write-Progress -Activity "Setting up jobs..." -Id 1 -Status "Current IP-Address: $IPv4Address" -PercentComplete $Progress_Percent
                            
            # Create new job
            $Job = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock).AddParameters($ScriptParams)
            $Job.RunspacePool = $RunspacePool
            
            $JobObj = [pscustomobject] @{
                RunNum = $i - $StartIPv4Address_Int64
                Pipe   = $Job
                Result = $Job.BeginInvoke()
            }

            # Add job to collection
            [void]$Jobs.Add($JobObj)
        }

        Write-Verbose -Message "Waiting for jobs to complete & starting to process results..."

        # Total jobs to calculate percent complete, because jobs are removed after they are processed
        $Jobs_Total = $Jobs.Count

        # Process results, while waiting for other jobs
        Do {
            # Get all jobs, which are completed
            $Jobs_ToProcess = $Jobs | Where-Object -FilterScript { $_.Result.IsCompleted }
    
            # If no jobs finished yet, wait 500 ms and try again
            if ($null -eq $Jobs_ToProcess) {
                Write-Verbose -Message "No jobs completed, wait 250ms..."

                Start-Sleep -Milliseconds 250
                continue
            }
            
            # Get jobs, which are not complete yet
            $Jobs_Remaining = ($Jobs | Where-Object -FilterScript { $_.Result.IsCompleted -eq $false }).Count

            # Catch when trying to divide through zero
            try {            
                $Progress_Percent = 100 - (($Jobs_Remaining / $Jobs_Total) * 100) 
            }
            catch {
                $Progress_Percent = 100
            }

            Write-Progress -Activity "Waiting for jobs to complete... ($($Threads - $($RunspacePool.GetAvailableRunspaces())) of $Threads threads running)" -Id 1 -PercentComplete $Progress_Percent -Status "$Jobs_Remaining remaining..."
        
            Write-Verbose -Message "Processing $(if($null -eq $Jobs_ToProcess.Count){"1"}else{$Jobs_ToProcess.Count}) job(s)..."

            # Processing completed jobs
            foreach ($Job in $Jobs_ToProcess) {       
                # Get the result...     
                $Job_Result = $Job.Pipe.EndInvoke($Job.Result)
                $Job.Pipe.Dispose()

                # Remove job from collection
                $Jobs.Remove($Job)
            
                # Check if result contains status
                if ($Job_Result.Status) {        
                    if ($AssignVendorToMAC) {           
                        $Vendor = [String]::Empty

                        # Check if MAC is null or empty
                        if (-not([String]::IsNullOrEmpty($Job_Result.MAC))) {
                            # Split it, so we can search the vendor (XX-XX-XX-XX-XX-XX to XXXXXX)
                            $MAC_VendorSearch = $Job_Result.MAC.Replace("-", "").Substring(0, 6)
                                    
                            $Vendor = $OUIHashTable.Get_Item($MAC_VendorSearch)
                        }

                        [pscustomobject] @{
                            IPv4Address  = $Job_Result.IPv4Address
                            Status       = $Job_Result.Status
                            Hostname     = $Job_Result.Hostname
                            MAC          = $Job_Result.MAC
                            Vendor       = $Vendor  
                            BufferSize   = $Job_Result.BufferSize
                            ResponseTime = $Job_Result.ResponseTime
                            TTL          = $ResuJob_Resultlt.TTL
                        } | Select-Object -Property $PropertiesToDisplay
                    }
                    else {
                        $Job_Result | Select-Object -Property $PropertiesToDisplay
                    }                            
                }
            } 

        } While ($Jobs.Count -gt 0)

        Write-Verbose -Message "Closing RunspacePool and free resources..."

        # Close the RunspacePool and free resources
        $RunspacePool.Close()
        $RunspacePool.Dispose()

        Write-Verbose -Message "Script finished at $(Get-Date)"
    }

    End {
        
    }
}

function Get-IpamManagedIPs {
    # Fetch all IP addresses managed by IPAM
    $ipamIPs = Get-IpamAddress -AddressFamily IPv4
    
    # Return only the IpAddress property for each entry
    return $ipamIPs | Select-Object -ExpandProperty IpAddress
}

function Compare-IPs {
    param (
        [array]$ScannedIPs,
        [array]$IpamIPs
    )

    # Find IPs that are in the scanned list but not in IPAM
    $missingInIpam = $ScannedIPs | Where-Object { $_ -notin $IpamIPs }

    if ($missingInIpam.Count -gt 0) {
        Write-Verbose "The following IPs are active but not present in IPAM:"
        $missingInIpam | Select-Object -ExpandProperty IPAddressToString
    } else {
        Write-Host "All scanned IPs are present in IPAM."
    }
}

function ScanAndCompare-IPAM {
    Param(
        [Parameter(
            ParameterSetName = 'CIDR',
            Position = 0,
            Mandatory = $true,
            HelpMessage = 'IPv4-Address which is in the subnet')]

        [Parameter(
            ParameterSetName = 'Mask',
            Position = 0,
            Mandatory = $true,
            HelpMessage = 'IPv4-Address which is in the subnet')]
        [IPAddress]$IPv4Address,

        [Parameter(
            ParameterSetName = 'CIDR',        
            Position = 1,
            Mandatory = $true,
            HelpMessage = 'CIDR like /24 without "/"')]
        [ValidateRange(0, 31)]
        [Int32]$CIDR
    )

    # Get active IPs from Layer 3 scan
    $scannedIPs = Invoke-IPv4NetworkScanPS -IPv4Address $IPv4Address -CIDR $CIDR | Select-Object -ExpandProperty IPv4Address

    # Get IPs from IPAM
    $ipamIPs = Get-IpamManagedIPs

    # Compare the results
    Compare-IPs -ScannedIPs $scannedIPs -IpamIPs $ipamIPs
}

function Test-IPAMMissingActiveIPv4StaticIPs {
    [CmdletBinding()]
    param()

    $subnets = Get-IpamSubnet -AddressFamily IPv4

    foreach ($subnet in $subnets) {
        $networkID, $cidr = $subnet.NetworkID.Split("/")

        Write-Verbose "Scanning Subnet: $networkID/$cidr"
        ScanAndCompare-IPAM -IPv4Address $networkID -CIDR $cidr
    }
}

function Add-IPAMMissingActiveIPv4StaticIPs {
    [CmdletBinding()]
    param()

    $ipaddresses = Test-IPAMMissingActiveIPv4StaticIPs

    foreach ($ipaddress in $ipaddresses) {

        Write-Verbose "Adding IP to IPAM: $ipaddress"
        Add-IpamAddress -IpAddress $ipaddress -PassThru
    }
}