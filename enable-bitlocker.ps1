if ($(Get-BitLockerVolume | Where-Object { $_.MountPoint -eq "C:" -and $_.ProtectionStatus -eq "On" }).Count -lt 1) {
    $key = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\FVE"
    if (!(Test-Path $key)) { New-Item $key }

    Set-ItemProperty -Path $key -Name UseAdvancedStartup -Value 1
    Set-ItemProperty -Path $key -Name EnableBDEWithNoTPM -Value 1

    $bitLockerPassword = Read-Host -Prompt "Enter password for bitlocker" -AsSecureString
    # this is not working on the VM ...
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes256 –UsedSpaceOnly -PasswordProtector -Password $bitLockerPassword
}