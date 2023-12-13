<# Scriptheader
.Synopsis 
    Short description of script purpose
.DESCRIPTION 
    Detailed description of script purpose
.NOTES 
   Created by: 
   Modified by: 
 
   Changelog: 
 
   To Do: 
.PARAMETER Debug 
    If the Parameter is specified, script runs in Debug mode
.EXAMPLE 
   Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error 
   Writes the message to the specified log file as an error message, and writes the message to the error pipeline. 
.LINK 
   https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0 
#>

param(
    [string]$XMLName = "config.xml",
    [switch]$Debug
)

#region loading modules, scripts & files
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
#
# load configuration XML(s)
$XMLPath = Join-Path $here -ChildPath $XMLName
[xml]$ConfigFile = Get-Content -Path $XMLPath
#
# we write one logfile and append each script execution
[string]$global:Logfile = $ConfigFile.Configuration.Logfile.Name
If ($Logfile -eq "Default"){
    $global:Logfile = Join-Path $here -ChildPath "ScriptTemplate.log"
}
$lfTmp = $global:Logfile.Split(".")
$global:Logfile = $lfTmp[0] + (Get-Date -Format yyyyMMdd) + "." + $lfTmp[1]
#
# Debug Mode
# If the parameter '-Debug' is specified or debug in XMLfile is set to "true", script activates debug mode
# when debug mode is active, debug messages will be dispalyed in console windows
#
If ($ConfigFile.Configuration.debug -eq "true"){
    $Debug = $true
}
#
If ($Debug){
    $DebugPreference = "Continue"
} else {$DebugPreference = "SilentlyContinue"}
#
#endregion

#region functions
function  Write-Log {
    param
    (
      [Parameter(Mandatory=$true)]
      $Message
    )
    If($Debug){
      Write-Debug -Message $Message
    }
  
    $msgToWrite =  ('{0} :: {1}' -f (Get-Date -Format yyy-MM-dd_HH-mm-ss),$Message)
  
    if($global:Logfile)
    {
      $msgToWrite | out-file -FilePath $global:Logfile -Append -Encoding utf8
    }
  }

function Get-Group {
  param (
    $Credentials = "none",
    $SearchBase = "none",
    $Server = "none",
    $Pattern = "none"
  )
  Write-Log -Message "start function Get-Group"
  Write-Log -Message ('authenticate at {0} using {1}' -f $Server,$Credentials.Username)
  $Filter = "Name -like '" + $Pattern + "'"
  [array]$ADGroups = @()
  $ADGroups = Get-ADGroup -Server $Server -Credential $Credentials -Filter $Filter -SearchBase $SearchBase

  Write-Log -Message "cleanup"
  Remove-Variable -Name Credentials
  Remove-Variable -Name Filter
  Remove-Variable -Name Server
  Remove-Variable -Name Pattern
  Return $ADGroups
  Write-Log -Message "end function Get-Group"
}
#endregion

#region write basic infos to log
Write-Log -Message '------------------------------- START -------------------------------'
$ScriptStart = "Script started at:               " + (Get-date)
Write-Log -Message $ScriptStart
If($Debug){
  Write-Log -Message "Debug Mode is:                   enabled"
} else {
  Write-Log -Message "Debug Mode is:                   disabled"
}
Write-Log -Message "PowerShell Script Path is:       $here"
Write-Log -Message "XML Config file is:              $XMLPath"
Write-Log -Message "LogFilePath is:                  $LogFile"
#endregion

#region read data from XML file
Write-Log -Message "start region read data from XML file"
[xml]$DataSource = Get-Content -Path $XMLPath

# prepare Variables
[string]$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
[string]$AD1DCName = $DataSource.Configuration.AD1.DC
[string]$AD1DN = $DataSource.Configuration.AD1.DN
[string]$AD1GroupFilter = $DataSource.Configuration.AD1.Filter.Pattern
[array]$AD1OUList = $DataSource.Configuration.AD1.OUList

# dump Variables used:
Write-Log -Message "Dumping read values to Log..."
Write-Log -Message ('Current User Context:            {0}' -f $CurrentUser)
Write-Log -Message ('AD1 DC Name:                     {0}' -f $AD1DCName)
Write-Log -Message ('AD1 DN:                          {0}' -f $AD1DN)
#Write-Log -Message ('AD1 Group Filter:                {0}' -f $AD1GroupFilter)
Write-Log -Message ('AD1 OU List:                     {0}' -f $AD1OUList)
#foreach ($Service in $DataSource.Configuration.Service){Write-Log -Message ('Service Name:                    {0}' -f $Service.Name)}
Write-Log -Message "end region read data from XML file"
#endregion

#region Load Modules
Write-Log -Message "::"
Write-Log -Message "start region Load Modules"
$ModuleName = "ActiveDirectory"
Write-Log -Message "Loading Module $ModuleName"
Import-Module $ModuleName

Write-Log -Message "Cleanup"
Remove-Variable -Name ModuleName

Write-Log -Message "end region Load Modules"
#endregion Load Modules

#region Read Info from AD1
Write-Log -Message "::"
Write-Log -Message "start region Read Info from AD1"

##check if credentials exist
Write-Log -Message "Import AD1 Credentials from file"
$AD1CredsExist = Test-Path -Path $here\AD1Creds.xml
if (!($AD1CredsExist)) {
  <# Action to perform if the condition is true #>
  Write-Log -Message "Credentials for ActiveDirectory 1 have not been created. Exit script now."
  Write-Log -Message '-------------------------------- End -------------------------------'
  Remove-Variable -Name AD1CredsExist
  break
} else {
  <# Action when all if and elseif conditions are false #>
  Write-Log -Message "Importing existing Credentials from XML file"
  $AD1Creds = Import-Clixml -Path $here\AD1Creds.xml
}
Write-Log -Message ('Credentials of {0} successfully imported' -f $AD1Creds.UserName)

## read groups from AD1
[array]$AD1GroupsToProcess = @()
#[array]$OUs = @()
$collection = $AD1OUList.Split(',')

##query groups for each OU found
foreach ($currentItemName in $collection) {
  <# $currentItemName is the current item #>
  $currentItemName = $DataSource.Configuration.AD1.$currentItemName
  $SearchPath = "OU=" + $currentItemName.Name + "," + $AD1DN
  $Patternlist = ($currentItemName.GroupNames).Split(',')
  
  ##query only groups that match specified patterns
  foreach ($Pattern in $Patternlist) {
    <# $Pattern is tPatternlist$Patternlist item #>
    $SearchPattern = $Pattern + $currentItemName.Name + "." + $currentItemName.Pattern + "*"
    $GroupsReturned = Get-Group -Server $AD1DCName -Credentials $AD1Creds -Pattern $SearchPattern -SearchBase $SearchPath
    $AD1GroupsToProcess += $GroupsReturned
  }

  ##cleanup
  Remove-Variable -Name currentItemName
  Remove-Variable -Name GroupsReturned
  Remove-Variable -Name Pattern
  Remove-Variable -Name Patternlist
  Remove-Variable -Name Searchpath
  Remove-Variable -Name SearchPattern
}

##cleanup query groups
Remove-Variable -Name collection

Write-Log -Message ('Querying groups done. Found {0} group(s) to process.' -f $AD1GroupsToProcess.count)

##query group users
Write-Log -Message "getting users from groups"
[array]$AD1UsersToProcess = @()
$collection = $AD1GroupsToProcess
foreach ($currentItemName in $collection) {
  <# $currentItemName is the current item #>
  [array]$FoundUsers = @()
  $FoundUsers = Get-ADGroupMember -Identity $currentItemName
  $AD1UsersToProcess += $FoundUsers

  Remove-Variable -Name currentItemName
  Remove-Variable -Name FoundUsers
}

##cleanup query users
Remove-Variable -Name collection

Write-Log -Message ('Querying users done. Found {0} users(s) to process.' -f $AD1UsersToProcess.count)

Write-Log -Message "cleanup"
#Remove-Variable -Name ADGroups
#Remove-Variable -Name AD1Groups
Remove-Variable -Name AD1CredsExist

Write-Log -Message "end region Read Info from AD1"
#endregion 


#region Cleanup
Remove-Variable -Name AD1GroupsToProcess
Remove-Variable -Name AD1UsersToProcess
Remove-Variable -Name DataSource

#endregion
Write-Log -Message '-------------------------------- End -------------------------------'