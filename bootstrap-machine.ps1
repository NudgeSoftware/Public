# variables
$nudgeDir = "C:\ProgramData\Nudge"
$setupDir = "$nudgeDir\machine-setup"
$codeDir = "C:\Code"
$userDir = "C:\Users\$env:UserName"
$logFile = "$env:LocalAppData\Boxstarter\Boxstarter.log"

# Prerequisite Validation
$os = Get-CimInstance Win32_OperatingSystem
$prerequisites = New-Object PSObject -Property @{
    OSHasVersion = $os.Version -gt 11
    OSHasArchitecture = $os.OSArchitecture -eq '64-bit'
    OSHasType = ($os.Caption -like '*Pro') -or ($os.Caption -like '*Enterprise')
    UserNameValid = $env:UserName -notlike '* *'
    UserMicrosoftAccount = $true
}
if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType -or !$prerequisites.UserNameValid -or !$prerequisites.UserMicrosoftAccount) {
    if (!$prerequisites.OSHasVersion -or !$prerequisites.OSHasArchitecture -or !$prerequisites.OSHasType) { $host.ui.WriteErrorLine("Minimum supported version of Windows is Windows 10 Pro, 64-bit. You are running $($os.Caption), $($os.OSArchitecture)") }
    if (!$prerequisites.UserNameValid) { $host.ui.WriteErrorLine("UserName ($env:UserName) must not contain spaces: Modify in Start -> User Accounts before continuing") }
    if (!$prerequisites.UserMicrosoftAccount) { $host.ui.WriteErrorLine("User account must be linked to Microsoft account (see https://support.microsoft.com/en-us/help/17201/windows-10-sign-in-with-a-microsoft-account)") }
    Exit
}

$lockFile = "$setupDir\bootstrap-machine.lock"
if (!(Test-Path $lockFile -NewerThan (Get-Date).AddHours(-2))) {
    try {
        # chocolatey initial setup
        choco feature enable -n=allowGlobalConfirmation -y
        choco feature enable -n=autoUninstaller -y

        # Windows setup
        Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions -EnableShowFullPathInTitleBar
        Disable-InternetExplorerESC
        Update-ExecutionPolicy
        Update-ExecutionPolicy Unrestricted
        Install-WindowsUpdate  -AcceptEula
        if (Test-PendingReboot) { Invoke-Reboot }

        Enable-MicrosoftUpdate
        Enable-UAC

    } catch {
        $logFile
    }
}
New-Item $lockFile -Force

if (!(Test-Path $setupDir)) {
    New-Item -Path $setupDir -type Directory
}


$settingsPath = "$nudgeDir\settings.ini"
$settings = @{}
if (Test-Path $settingsPath) {
    Get-Content $settingsPath | foreach-object -begin {$settings=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $settings.Add($k[0], $k[1]) } }
}

Write-Host ">> Configure settings"
if (!($settings["email"])) {  
    $settings["email"] = Read-Host "What email do you use with git? "  
} 

if (!($settings["username"])) {
    $settings["username"] = Read-Host "Input your Computer username (ENTER for $env:UserName) "
    if (!($settings["username"])) {
        $settings["username"] = $env:UserName
    }
}
if (!($settings["name"])) {
    $settings["name"] = Read-Host "Input your Nudge name (ideally $($settings["username"]), but if that is not unique at Nudge then a unique value for all nudge dev resources -- ENTER for $($settings["username"])) "
    if (!($settings["name"])) {
        $settings["name"] = $settings["username"]
    }
}

if (Test-Path $settingsPath) {
    Remove-Item $settingsPath
}
foreach ($i in $settings.keys) {
    Add-Content -Path $settingsPath -Value "$i=$($settings[$i])"
}

$profile = "C:\Users\$($settings['username'])"
$bashProfile = "/c/Users/$($settings['username'])"

# hack to get lessmsi available
$env:Path += ";C:\ProgramData\chocolatey\bin"

cinst dotnet3.5 -y
cinst lessmsi -y
cinst webpicmd -y

# Windows Updates (this takes time)
Install-WindowsUpdate -AcceptEula

# install Git & associated
cinst git -y -params '"/GitAndUnixToolsOnPath /NoAutoCrlf"'
cinst gitextensions -y
cinst poshgit -y
cinst P4Merge -y

# Configure git
$registryPath = "HKCU:\Software\GitExtensions"
if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
New-ItemProperty -Path $registryPath -Name "gitssh" -Value "" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "gitcommand" -Value "" -PropertyType String -Force | Out-Null

git config --global user.name $settings["name"]
git config --global user.email $settings["email"]
git config --global core.autocrlf False
git config --global merge.tool p4merge
git config --global diff.guitool p4merge
git config --global difftool.p4merge.path "C:/Program Files/Perforce/p4merge.exe"
git config --global difftool.p4merge.cmd '\"C:/Program Files/Perforce/p4merge.exe\" \"$REMOTE\" \"$MERGED\"'
git config --global mergetool.p4merge.path "C:/Program Files/Perforce/p4merge.exe"
git config --global mergetool.p4merge.cmd '\"C:/Program Files/Perforce/p4merge.exe\" \"$BASE\" \"$LOCAL\" \"$REMOTE\" \"$MERGED\"'

if (!(Test-Path "$profile\.ssh")) {
    cd $profile
    mkdir .ssh
}

cinst boxstarter -y

$codeDir = "C:\Code"
if (!(Test-Path $codeDir)) {
    New-Item -Path $codeDir -type Directory
}
cd $codeDir

if (!(Test-Path "$codeDir\Tooling")) {
    # git ssh setup:
    if (!(Test-Path "$profile\.ssh\id_rsa")) {
        ssh-keygen -q -C $settings["email"] -f $bashProfile/.ssh/id_rsa
    }

    ssh-agent -s
    ssh-add $bashProfile/.ssh/id_rsa
    Get-Content "$profile\.ssh\id_rsa.pub" | clip
    Start-Process -FilePath "https://github.com/settings/ssh"

    Write-Host "Copied the full contents of $profile\.ssh\id_rsa (currently in your clipboard):"
    Read-Host "Go to https://github.com/settings/ssh and add as a new key, then press ENTER"
    ssh -T git@github.com

    # clone repo
    git clone git@github.com:NudgeSoftware/Tooling.git
}

bash /c/Code/Tooling/config/dev/bootstrap-machine.sh --user=$settings["name"]
