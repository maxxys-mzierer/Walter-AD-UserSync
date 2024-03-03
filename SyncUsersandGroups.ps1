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
  Write-Log -Message ('searching for group {0} in {1}' -f $Pattern,$SearchBase)
  [array]$ADGroups = @()
  $ADGroups = Get-ADGroup -Server $Server -Credential $Credentials -Filter $Filter -SearchBase $SearchBase

  #Write-Log -Message "cleanup"
  Remove-Variable -Name Credentials
  Remove-Variable -Name Filter
  Remove-Variable -Name Server
  Remove-Variable -Name Pattern
  Return $ADGroups
  Write-Log -Message "end function Get-Group"
}

function New-OU {
  param (
    $Credentials = "default",
    $Name = "default",
    $Path = "default",
    $Server = "default"
  )
  Write-Log -Message "start function New-OU"
  New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false -Server $Server -Credential $Credentials
  Write-Log -Message ('OU {0} created in {1}' -f $Name,$Path)

  Write-Log -Message "cleanup"
  Remove-Variable -Name Name
  Remove-Variable -Name Path
  Write-Log -Message "end function New-OU"
}

function New-Group {
  param (
    $Credentials = "default",
    $Name = "default",
    $Path = "default",
    $Server = "default",
    $Scope = "Global",
    $Category = "Security"
  )
  Write-Log -Message "start function New-Group"
  
  New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory $Category -GroupScope $Scope -DisplayName $Name -Path $Path
  Write-Log -Message "end function New-Group"
}

function New-User {
  param (
    $Name = "default",
    $Password = "Start1234!",
    $Path = "default",
    $SAM = "default"
  )
  Write-Log -Message "start function New-User"
  $Pwd = ConvertTo-SecureString $Password -AsPlainText -Force
  New-ADUser -Name $Name -AccountPassword $Pwd -Enabled 1 -Path $Path -SamAccountName $SAM
  Write-Log -Message "end function New-User"
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
[array]$AD1OUList = $DataSource.Configuration.AD1
[string]$AD2DCName = $DataSource.Configuration.AD2.DC
[string]$AD2DN = $DataSource.Configuration.AD2.DN

# dump Variables used:
Write-Log -Message "Dumping read values to Log..."
Write-Log -Message ('Current User Context:            {0}' -f $CurrentUser)
Write-Log -Message ('AD1 DC Name:                     {0}' -f $AD1DCName)
Write-Log -Message ('AD1 DN:                          {0}' -f $AD1DN)
foreach ($OU in $DataSource.Configuration.AD1.OU){Write-Log -Message ('AD1 OU Name:                     {0}' -f $OU.Name)}
Write-Log -Message ('AD2 DC Name:                     {0}' -f $AD2DCName)
Write-Log -Message ('AD2 DN:                          {0}' -f $AD2DN)
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
#$collection = $AD1OUList.Split(',')
$collection = $DataSource.Configuration.AD1.OU
#$FilteredGroups = @()
$TargetGroups = @()

##query groups for each OU found
foreach ($currentItemName in $DataSource.Configuration.AD1.OU) {
  <# $currentItemName is the current item #>
  #$currentItemName = $DataSource.Configuration.AD1.$currentItemName
  $FilteredGroups = @()
  $SearchPath = "OU=" + $currentItemName.Name + "," + $AD1DN
  $SearchPattern = "*"
  $GroupsReturned = Get-Group -Server $AD1DCName -Credentials $AD1Creds -Pattern $SearchPattern -SearchBase $SearchPath
  Write-Log -Message ('Found {0} groups in this OU' -f $GroupsReturned.count)
  #$AD1GroupsToProcess += $GroupsReturned
  $Patternlist = ($currentItemName.GroupNames).Split(',')
  
  ##query only groups that match specified patterns
  Write-Log -Message "filtering for relevant groups"
  foreach ($Pattern in $Patternlist) {
    #$SearchPattern = $Pattern + $currentItemName.Name + $currentItemName.Pattern + "*"
    $SearchPattern = $Pattern + $currentItemName.Name + $currentItemName.Pattern

    foreach ($Group in $GroupsReturned) {
      if ($Group -match $SearchPattern) {
        <# Action to perform if the condition is true #>
        $FilteredGroups += $Group
        $TargetGroups += $Group
      }
      #cleanup
      Remove-Variable -Name Group
    }
    #$GroupsReturned = Get-Group -Server $AD1DCName -Credentials $AD1Creds -Pattern $SearchPattern -SearchBase $SearchPath
    #$AD1GroupsToProcess += $GroupsReturned
  }
  Write-Log -Message ('Filtered out {0} groups in this OU' -f $FilteredGroups.count)

  ##cleanup
  Remove-Variable -Name currentItemName
  Remove-Variable -Name FilteredGroups
  Remove-Variable -Name GroupsReturned
  Remove-Variable -Name Pattern
  Remove-Variable -Name Patternlist
  Remove-Variable -Name Searchpath
  Remove-Variable -Name SearchPattern
}

##cleanup query groups
Remove-Variable -Name collection

Write-Log -Message ('Querying groups done. Found a total of {0} group(s) to process.' -f $TargetGroups.count)

<##filter groups
Write-Log -Message "Now filterting Results for Groups matching the search pattern"
#$TargetGroups = @()
$collection = $AD1GroupsToProcess
$Pattern = ".OT."
foreach ($currentItemName in $collection) {
  
  if ($currentItemName -match $Pattern) {
    
    $TargetGroups += $currentItemName
  }
  
  ##cleanup
  Remove-Variable -Name currentItemName
}

##cleanup filter groups
Remove-Variable -Name collection
Remove-Variable -Name Pattern

Write-Log -Message ('{0} groups are remaining after filtering.' -f $TargetGroups.Count)
##>

##query group users
Write-Log -Message "getting users from remaining groups"
[array]$AD1UsersToProcess = @()
$collection = $TargetGroups
foreach ($currentItemName in $collection) {
  <# $currentItemName is the current item #>
  [array]$FoundUsers = @()
  $FoundUsers = Get-ADGroupMember -Identity $currentItemName
  $AD1UsersToProcess += $FoundUsers

  Remove-Variable -Name currentItemName
  Remove-Variable -Name FoundUsers
}

##for development only
$FoundUsers = Get-ADUser -Filter * -SearchBase "OU=Users,OU=3428,DC=win,DC=dom,DC=sandvik,DC=com" -Server $AD1DCName -Credential $AD1Creds

##cleanup query users
Remove-Variable -Name collection

Write-Log -Message ('Querying users done. Found {0} users(s) to process.' -f $AD1UsersToProcess.count)

Write-Log -Message "cleanup"
#Remove-Variable -Name ADGroups
#Remove-Variable -Name AD1Groups
Remove-Variable -Name AD1CredsExist

Write-Log -Message "end region Read Info from AD1"
#endregion 

#region write Data to AD2
Write-Log -Message "::"
Write-Log -Message "start region write data to AD2"

##check if credentials exist
Write-Log -Message "Import AD2 Credentials from file"
$AD2CredsExist = Test-Path -Path $here\AD2Creds.xml
if (!($AD2CredsExist)) {
  <# Action to perform if the condition is true #>
  Write-Log -Message "Credentials for ActiveDirectory 2 have not been created. Exit script now."
  Write-Log -Message '-------------------------------- End -------------------------------'
  Remove-Variable -Name AD2CredsExist
  break
} else {
  <# Action when all if and elseif conditions are false #>
  Write-Log -Message "Importing existing Credentials from XML file"
  $AD2Creds = Import-Clixml -Path $here\AD2Creds.xml
}
Write-Log -Message ('Credentials of {0} successfully imported' -f $AD2Creds.UserName)

Write-log -Message "start Check and create OU's, if necessary"
foreach ($currentItemName in $DataSource.configuration.AD1.OU) {
  <# $currentItemName is the current item #>
  $Identity = "OU=" + $currentItemName.Name + "," + $AD2DN
  $ADPath = "AD:\$Identity"
  if ( [bool] (Test-Path $ADPath)) {
    <# Action to perform if the condition is true #>
    Write-Log -Message ('OU {0} already exist. Skip creation' -f $Identity)
  } else {
    Write-Log -Message ('OU {0} does not exist. Start creation' -f $Identity)
    New-OU -Name ($currentItemName.Name) -Path $AD2DN -Server $AD2DCName -Credentials $AD2Creds
    New-OU -Name "computers" -Path $Identity
    New-OU -Name "groups" -Path $Identity
    New-OU -Name "users" -Path $Identity
  }

  ##cleanup
  Remove-Variable -Name ADPath
  Remove-Variable -Name Identity
  Remove-Variable -Name currentItemName
}
Write-Log -Message "end Check and create OU's, if necessary"

Write-Log -Message "start creating AD Groups, if necessary"
$collection = $TargetGroups

foreach ($currentItemName in $collection) {
  <# $currentItemName is the current item #>
  Write-Log -Message ('First check, if group {0} already exist' -f $currentItemName.Name)
  $OUName = ($currentItemName.Name).substring(4,4)
  $SearchPath = "OU=" + $OUName + "," + $AD2DN
  $SearchPattern = "*"
  $GroupsReturned = Get-Group -Server $AD2DCName -Credentials $AD2Creds -Pattern $SearchPattern -SearchBase $SearchPath
  $GroupsReturnedNames = @()
  foreach ($Group in $GroupsReturned) {
    <# $currentItemName is the current item #>
    $GroupsReturnedNames += $Group.Name

  }
  Remove-Variable -Name Group

  if ($GroupsReturnedNames -notcontains ($currentItemName.Name)) {
    <# Action to perform if the condition is true #>
    Write-Log -Message "Group does not exist, let's create it"
    $GroupName = $currentItemName.Name
    $CreatePath = "OU=groups," + $SearchPath
    New-Group -Name $GroupName -Path $CreatePath
    #New-Group -Name $GroupName -Path $CreatePath -Credentials $AD2Creds -Server $AD2DCName
  }

  #Read & Create users
  Write-Log -Message "Read Group members and create them"
  $UsersToCreate = Get-ADGroupMember -Server $AD1DCName -Credential $AD1Creds -Identity "CN=DEMU3422.3422_groups_Projects_RedSea_mod,OU=Groups,OU=3422,DC=win,DC=dom,DC=sandvik,DC=com"
  foreach ($User in $UsersToCreate) {
    <# $User is tUsersTo$UsersToCreate item #>
    $CreatePath = "OU=users," + $SearchPath
    $UserName = $User.Name
    $UserSAM = $User.SamAccountName
    New-User -Name $UserName -SAM $UserSAM -Path $CreatePath
  }

  #$UsersToCreate = Get-ADGroupMember -Server $AD1DCName -Credential $AD1Creds -Identity $currentItemName
  #cleanup
  Remove-Variable -Name CreatePath
  Remove-Variable -Name GroupName
  Remove-Variable -Name GroupsReturned
  Remove-Variable -Name OUName
  Remove-Variable -Name SearchPath
  Remove-Variable -Name SearchPattern
  Remove-variable -Name User
  Remove-Variable -Name UserName
  Remove-Variable -Name UserSAM
  Remove-Variable -Name UsersToCreate
}
Write-Log -Message "end creating AD Groups"

Write-Log -Message "end region write data to AD2"
#endregion

#region Cleanup
Remove-Variable -Name AD1GroupsToProcess
Remove-Variable -Name AD1UsersToProcess
Remove-Variable -Name DataSource

#endregion
Write-Log -Message '-------------------------------- End -------------------------------'