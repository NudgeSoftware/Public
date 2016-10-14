cinst P4Merge -y

git config --global merge.tool p4merge
git config --global diff.guitool p4merge
git config --global difftool.p4merge.path "C:/Program Files/Perforce/p4merge.exe"
git config --global difftool.p4merge.cmd '\"C:/Program Files/Perforce/p4merge.exe\" \"$REMOTE\" \"$MERGED\"'
git config --global mergetool.p4merge.path "C:/Program Files/Perforce/p4merge.exe"
git config --global mergetool.p4merge.cmd '\"C:/Program Files/Perforce/p4merge.exe\" \"$BASE\" \"$LOCAL\" \"$REMOTE\" \"$MERGED\"'