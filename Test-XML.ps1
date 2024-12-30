
<#PSScriptInfo

.VERSION 1.0

.GUID 4a9c07a5-7f02-4884-a5e4-2644bb39088d

.AUTHOR Nelson Lopes

.COMPANYNAME 

.COPYRIGHT 

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

.DESCRIPTION 
 XML validation against XSD. 


#>

function Test-XML {
    param (
    [Parameter(ValueFromPipeline=$true, Mandatory=$true)]
        [string] $XmlFile,

        [Parameter(Mandatory=$true)]
        [string] $SchemaFile
    )

    [string[]]$Script:XmlValidationErrorLog = @()
    [scriptblock] $ValidationEventHandler = {
        $Script:XmlValidationErrorLog += $args[1].Exception.Message
    }

    $xml = New-Object System.Xml.XmlDocument
    $schemaReader = New-Object System.Xml.XmlTextReader $SchemaFile
    $schema = [System.Xml.Schema.XmlSchema]::Read($schemaReader, $ValidationEventHandler)
    $xml.Schemas.Add($schema) | Out-Null
    $xml.Load($XmlFile)
    $xml.Validate($ValidationEventHandler)

    if ($Script:XmlValidationErrorLog) {
        Write-Warning "$($Script:XmlValidationErrorLog.Count) errors found"
        Write-Error "$Script:XmlValidationErrorLog"
    }
    else {
        Write-Host "The XML file is OK!"
    }
}

