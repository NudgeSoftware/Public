﻿# variables
$user = Get-CimInstance Win32_UserAccount | Where-Object { $_.Caption -eq $(whoami) }
$ps = New-Object PSObject -Property @{
    NudgeDir = "C:\ProgramData\Nudge"
    SetupDir = "C:\ProgramData\Nudge\machine-setup"
    CodeDir = "C:\Code"
    UserDir = "C:\Users\$env:UserName"
    SshDir = "C:\Users\$env:UserName\.ssh"
    EmailAddressFile = "C:\ProgramData\Nudge\machine-setup\emailaddress.txt"
    LogFile = "$env:LocalAppData\Boxstarter\Boxstarter.log"
}
$bash = New-Object PSObject
foreach ($p in Get-Member -InputObject $ps -MemberType NoteProperty) {
     Add-Member -InputObject $bash -MemberType NoteProperty -Name $p.Name -Value $From.$($p.Name) –Force
     $bash.$($p.Name) = $($ps.$($p.Name) -replace "\\", "/" -replace "C:", "/c")
}

Write-Host "Logs are available in $($ps.LogFile)"

Write-Host $user
Write-Host $ps
Write-Host $bash

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
    try {
        # chocolatey initial setup
        choco feature enable -n=allowGlobalConfirmation -y
        choco feature enable -n=autoUninstaller -y

        # Windows setup
        Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
        Disable-InternetExplorerESC
        Update-ExecutionPolicy
        Update-ExecutionPolicy Unrestricted
        New-Item $lockFile -Force
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}

# git install
$lockFile = "$($ps.SetupDir)\install-git.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    try {
        cinst dotnet3.5 -y
        cinst lessmsi -y
        cinst webpicmd -y
        if (Test-PendingReboot) { Invoke-Reboot }

        # hack to get lessmsi available
        $env:Path += ";C:\ProgramData\chocolatey\bin"

        # install Git
        cinst git -y -params '"/GitAndUnixToolsOnPath /NoAutoCrlf"'
        cinst poshgit -y
        cinst gitextensions -y
        New-Item $lockFile -Force
        Invoke-Reboot
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}

# git install & setup
$lockFile = "$($ps.SetupDir)\setup-git.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    try {
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
        Invoke-Item "$($ps.SshDir)\id_rsa.pub"
        Start-Process -FilePath "https://github.com/settings/ssh"

        Write-Host "Copied the full contents of $($bash.SshDir)/id_rsa.pub (currently in your clipboard):"
        Read-Host "Go to https://github.com/settings/ssh and add as a new key, then press ENTER"
        ssh -T git@github.com
        New-Item $lockFile -Force
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}

$lockFile = "$($ps.SetupDir)\windows-update.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    if (Test-PendingReboot) { Invoke-Reboot }
    try {
        Install-WindowsUpdate  -AcceptEula
        if (Test-PendingReboot) { Invoke-Reboot }

        Enable-MicrosoftUpdate
        # TODO: bitlocker
        cinst boxstarter -y
        New-Item $lockFile -Force
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}


if (!(Test-Path $ps.CodeDir)) {
    New-Item -Path $ps.CodeDir -type Directory
}

if (!(Test-Path "$($ps.CodeDir)\Public")) {
    if (Test-PendingReboot) { Invoke-Reboot }
    try {
        cd $ps.CodeDir
        git clone git@github.com:NudgeSoftware/Public.git
        cp "$($ps.CodeDir)\Public\*" $ps.SetupDir
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}

if (!(Test-Path "$($ps.CodeDir)\Tooling")) {
    if (Test-PendingReboot) { Invoke-Reboot }
    try {
        cd $ps.CodeDir
        git clone git@github.com:NudgeSoftware/Tooling.git
        #cp "$($ps.CodeDir)\Tooling\*" $ps.SetupDir
    } catch {
        Invoke-Item $ps.LogFile
        throw
    }
}

# VS 2015 Update 3 required
# user script ??

Enable-UAC

