# Get-MailboxesItemAndSizeCSV
#  A really rough implementation BETA
#
#  Outputs A CSV in the current directory: mailbox_item_and_size.csv
#
#  Author: David Midlo (david@avartec.com)
#  Version: 0.0.1
#
#  Usage:
#     - use powershell's dot sourcing to import the function into your powershell session
#         . .\Get-MailboxesItemAndSizeCSV.ps1
#
#     - Run the command
#         Get-MailboxesItemAndSizeCSV
#
#     That's it!

function Get-MailboxesItemAndSizeCSV {
    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

    $mailboxes = Get-Mailbox -ResultSize Unlimited

    $results = @()

    foreach ($mailbox in $mailboxes) {
        Write-Host "Processing mailbox: $($mailbox.PrimarySmtpAddress)"

        # Fetch the folder statistics for the current mailbox
        $folders = Get-MailboxFolderStatistics -Identity $mailbox.UserPrincipalName


        $result = [PSCustomObject]@{
            UPN = $mailbox.UserPrincipalName
            ItemCount = 0
            Size = [Microsoft.Exchange.Data.ByteQuantifiedSize]::FromBytes(0) # Initialize with 0 bytes
        }

        foreach ($folder in $folders) {
            $result.ItemCount += $folder.ItemsInFolder
            $result.Size = [Microsoft.Exchange.Data.ByteQuantifiedSize]::FromBytes(
                $result.Size.ToBytes() + $folder.FolderSize.ToBytes()
            )
        }

        $results += $result
    }

    # Output the results
    $results | Sort-Object -Descending -Property ItemCount | Export-Csv -Path "mailbox_item_and_size.csv" -NoTypeInformation
}