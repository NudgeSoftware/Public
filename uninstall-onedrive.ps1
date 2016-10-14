# Remove OneDrive
Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Name "System.IsPinnedToNameSpaceTree" -Value 0
& "$($env:SystemRoot)\SysWOW64\OneDriveSetup.exe" /uninstall