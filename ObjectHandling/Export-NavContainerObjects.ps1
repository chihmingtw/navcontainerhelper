﻿<# 
 .Synopsis
  Export objects from a Nav container
 .Description
  Creates a session to the Nav container and launch the Export-NavApplicationObjects Cmdlet to export object
 .Parameter containerName
  Name of the container for which you want to enter a session
 .Parameter objectsFolder
  The folder to which the objects are exported (needs to be shared with the container)
  NOTE: The content of this folder will be deleted.
 .Parameter sqlCredential
  Credentials for the SQL admin user if using NavUserPassword authentication. User will be prompted if not provided
 .Parameter filter
  Specifies which objects to export (default is modified=Yes)
 .Parameter exportToNewSyntax
  Specifies whether or not to export objects in new syntax (default is true)
 .Example
  Export-NavContainerObject -containerName test -objectsFolder c:\programdata\navcontainerhelper\objects
 .Example
  Export-NavContainerObject -containerName test -objectsFolder c:\programdata\navcontainerhelper\objects -sqlCredential (get-credential -credential 'sa') -filter ""
#>
function Export-NavContainerObjects {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$containerName, 
        [Parameter(Mandatory=$true)]
        [string]$objectsFolder, 
        [Parameter(Mandatory=$false)]
        [string]$filter = "modified=Yes", 
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]$sqlCredential = $null,
        [ValidateSet('txt folder','txt folder (new syntax)','txt file','txt file (new syntax)','fob file')]
        [string]$exportTo = 'txt folder (new syntax)',
        [Obsolete("exportToNewSyntax is obsolete, please use exportTo instead")]
        [switch]$exportToNewSyntax = $true,
        [switch]$includeSystemObjects
    )

    if (!$exportToNewSyntax) {
        $exportTo = 'txt folder'
    }

    if ("$objectsFolder" -eq "$hostHelperFolder" -or "$objectsFolder" -eq "$hostHelperFolder\") {
        throw "The folder specified in ObjectsFolder will be erased, you cannot specify $hostHelperFolder"
    }

    $sqlCredential = Get-DefaultSqlCredential -containerName $containerName -sqlCredential $sqlCredential -doNotAskForCredential
    $containerObjectsFolder = Get-NavContainerPath -containerName $containerName -path $objectsFolder -throw

    $navversion = Get-NavContainerNavversion -containerOrImageName $imageName
    $version = [System.Version]($navversion.split('-')[0])
    $ignoreSystemObjects = ($version.Major -ge 14)

    Invoke-ScriptInNavContainer -containerName $containerName -ScriptBlock { Param($filter, $objectsFolder, [System.Management.Automation.PSCredential]$sqlCredential, $exportTo, $ignoreSystemObjects)

        if ($exportTo -eq 'fob file') {
            $objectsFile = "$objectsFolder\objects.fob"
        } else {
            $objectsFile = "$objectsFolder\objects.txt"
        }

        if (Test-Path $objectsFolder -PathType Container) {
            Get-ChildItem -Path $objectsFolder -Include * | Remove-Item -Recurse -Force
        } else {
            New-Item -Path $objectsFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }

        if ($ignoreSystemObjects) {
            if ($filter) {
                $filter += ";Id=1..1999999999"
            }
            else {
                $filter = "Id=1..1999999999"
            }
        }

        $filterStr = ""
        if ($filter) {
            $filterStr = " with filter '$filter'"
        }
        if ($exportTo.Contains('(new syntax)')) {
            Write-Host "Export Objects$filterStr (new syntax) to $objectsFile (container path)"
        } else {
            Write-Host "Export Objects$filterStr to $objectsFile (container path)"
        }

        $customConfigFile = Join-Path (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName "CustomSettings.config"
        [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
        $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
        $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
        $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
        if ($databaseInstance) { $databaseServer += "\$databaseInstance" }

        $params = @{ 'ExportTxtSkipUnlicensed' = $true }
        if ($sqlCredential) {
            $params += @{ 'Username' = $sqlCredential.UserName; 'Password' = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlCredential.Password))) }
        }
        if ($exportTo.Contains('(new syntax)')) {
            $params += @{ 'ExportToNewSyntax' = $true }
        }

        Export-NAVApplicationObject @params -DatabaseName $databaseName `
                                    -Path $objectsFile `
                                    -DatabaseServer $databaseServer `
                                    -Force `
                                    -Filter "$filter" | Out-Null

        if ($exportTo.Contains("folder")) {
            Write-Host "Split $objectsFile to $objectsFolder (container paths)"
            if ((Test-Path $objectsFile) -and ((Get-Item -Path $objectsFile).Length -gt 0)) {
                Split-NAVApplicationObjectFile -Source $objectsFile `
                                               -Destination $objectsFolder
            }
            Remove-Item -Path $objectsFile -Force -ErrorAction Ignore
        }
    
    }  -ArgumentList $filter, $containerObjectsFolder, $sqlCredential, $exportTo, $ignoreSystemObjects
}
Export-ModuleMember -function Export-NavContainerObjects
