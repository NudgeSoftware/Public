# variables (both powershell and bash versions)
$user = Get-CimInstance Win32_UserAccount | Where-Object { $_.Caption -eq $(whoami) }
$ps = New-Object PSObject -Property @{
    NudgeDir = "C:\ProgramData\Nudge"
    SetupDir = "C:\ProgramData\Nudge\machine-setup"
    CodeDir = "C:\Code"
    UserDir = "$env:USERPROFILE" 
    SshDir = "$env:USERPROFILE\.ssh"
    EmailAddressFile = "C:\ProgramData\Nudge\machine-setup\emailaddress.txt"
    LogFile = "$env:LocalAppData\Boxstarter\Boxstarter.log"
}
$bash = New-Object PSObject
foreach ($p in Get-Member -InputObject $ps -MemberType NoteProperty) {
     Add-Member -InputObject $bash -MemberType NoteProperty -Name $p.Name -Value $From.$($p.Name) –Force
     $bash.$($p.Name) = $($ps.$($p.Name) -replace "\\", "/" -replace "C:", "/c")
}

# logging
invoke-expression 'cmd /c start powershell -Command { ""; "** See $($ps.LogFile) for all logs"; ""; Get-Content $ps.LogFile -Wait }'

# Prerequisite Validation
$os = Get-CimInstance Win32_OperatingSystem
$prerequisites = New-Object PSObject -Property @{
    OSHasVersion = $os.Version -gt 10
    OSHasArchitecture = $os.OSArchitecture -eq '64-bit'
    OSHasType = ($os.Caption -like '*Pro*') -or ($os.Caption -like '*Enterprise*')
    UserNameValid = $env:UserName -notlike '* *'
}
if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType -or !$prerequisites.UserNameValid) {
    if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType) { $host.ui.WriteErrorLine("Minimum supported version of Windows is Windows 10 Pro, 64-bit. You are running $($os.Caption), $($os.OSArchitecture)") }
    if (!$prerequisites.UserNameValid) { $host.ui.WriteErrorLine("UserName ($env:UserName) must not contain spaces: Modify in Start -> User Accounts before continuing") }
#    if (!$prerequisites.UserMicrosoftAccount) { $host.ui.WriteErrorLine("User account must be linked to Microsoft account (see https://support.microsoft.com/en-us/help/17201/windows-10-sign-in-with-a-microsoft-account)") }
    Exit
}
Write-Host "Prerequisites satisfied!"

if (!(Test-Path $ps.EmailAddressFile)) {
    $emailAddress = Read-Host "What email do you use with git? "  
    New-Item $ps.EmailAddressFile -Force
    Add-Content -Path $ps.EmailAddressFile -Value "$emailAddress"
} else {
    $emailAddress = Get-Content -Path $ps.EmailAddressFile
}
Write-Host "Email Address: $emailAddress"

# initial settings for windows & boxstarter
$lockFile = "$($ps.SetupDir)\bootstrap-machine.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    # chocolatey initial setup
    choco feature enable -n=allowGlobalConfirmation -y
    choco feature enable -n=autoUninstaller -y

    # Windows setup
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
    Disable-InternetExplorerESC
    Update-ExecutionPolicy
    Update-ExecutionPolicy Unrestricted
    New-Item $lockFile -Force
}

# git install
$lockFile = "$($ps.SetupDir)\install-git.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    #cinst dotnet3.5 -y
    #cinst lessmsi -y
    #cinst webpicmd -y
    #if (Test-PendingReboot) { Invoke-Reboot }

    # hack to get lessmsi available
    #$env:Path += ";C:\ProgramData\chocolatey\bin"

    # install Git
    cinst git -y -params '"/GitAndUnixToolsOnPath /NoAutoCrlf"'
    cinst poshgit -y
    cinst gitextensions -y
    New-Item $lockFile -Force
    Invoke-Reboot
}

# git setup
$lockFile = "$($ps.SetupDir)\setup-git.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    git config --global user.name $user.FullName
    git config --global user.email $emailAddress
    git config --global core.autocrlf False

    # git ssh setup
    if (!(Test-Path "$($ps.SshDir)\id_rsa")) {
        ssh-keygen -q -C $emailAddress -f "$($bash.SshDir)/id_rsa"
    }

    ssh-agent -s
    ssh-add "$($bash.SshDir)/id_rsa"
    Get-Content "$($ps.SshDir)\id_rsa.pub" | clip

    # because of the context, can't use Edge to open github at this point
    cinst googlechrome -y
    & notepad "$($ps.SshDir)\id_rsa.pub"
    & "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" "https://github.com/settings/ssh"

    Write-Host "Copied the full contents of $($bash.SshDir)/id_rsa.pub (currently in your clipboard):"
    Read-Host "Go to https://github.com/settings/ssh and add as a new key, then press ENTER"
    ssh -T git@github.com
    New-Item $lockFile -Force
}

$lockFile = "$($ps.SetupDir)\windows-update.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    Install-WindowsUpdate  -AcceptEula
    if (Test-PendingReboot) { Invoke-Reboot }

    Enable-MicrosoftUpdate
    cinst boxstarter -y
    New-Item $lockFile -Force
}


if (!(Test-Path $ps.CodeDir)) {
    New-Item -Path $ps.CodeDir -type Directory
}

$repo = "Public"
if (!(Test-Path "$($ps.CodeDir)\$repo")) {
    git clone git@github.com:NudgeSoftware/$repo.git "$($ps.CodeDir)\$repo"
    cp "$($ps.CodeDir)\$repo\*" $ps.SetupDir
}

$repo = "Tooling"
if (!(Test-Path "$($ps.CodeDir)\$repo")) {
    git clone git@github.com:NudgeSoftware/$repo.git "$($ps.CodeDir)\$repo"
    cp "$($ps.CodeDir)\$repo\config\dev\*" $ps.SetupDir
}

$repo = "Relationships"
if (!(Test-Path "$($ps.CodeDir)\$repo")) {
    git clone git@github.com:NudgeSoftware/$repo.git "$($ps.CodeDir)\$repo"
}

# productivity tools

# DSC for windows features, IIS setup, frameworks
# TODO: rewrite "localhost" to $env:ComputerName ?
& "$($ps.SetupDir)\windows-configuration.ps1"
#Start-DSCConfiguration -Path "$($ps.SetupDir)\WindowsConfiguration" -Verbose -Wait -Force
# TODO: tomcat -- can this be hosted in docker instead ??

# node.js, client side tooling
# server tooling
# configure IIS, shared config
# create dev certs
# configure Tomcat

# visual studio install, resharper tools
# intellij
# datastax dev centre
# sql management studio

# hosts file setup
# azure sdk setup

# environment variable config

& "$($ps.SetupDir)\create-database.ps1" -setupDir $ps.SetupDir



# install Editors & IDEs (some is done in custom..)
# 

# https://gist.github.com/NickCraver/7ebf9efbfd0c3eab72e9 for some custom setup?
# VS 2015 Update 3 required
# can I use DSC or ansible for some of the more standard stuff (windows features, IIS setup, frameworks, etc)?
# see http://mikefrobbins.com/2015/11/05/solving-dsc-problems-on-windows-10-writing-powershell-code-that-writes-powershell-code-for-you/

# TODO: other scripts in Tooling repo

& "$($ps.SetupDir)\custom-scripts.ps1" -emailAddress $emailAddress

# TODO: potentially use this https://www.powershellgallery.com/packages/xBitlocker/1.1.0.0/Content/Examples%5CConfigureBitlockerOnOSDrive%5CConfigureBitlockerOnOSDrive.ps1
& "$($ps.SetupDir)\enable-bitlocker.ps1"
Enable-UAC

