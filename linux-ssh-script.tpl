add-content -path c:/users/smoke/.ssh/config -value @'
Host ${hostname}
  HostName ${hostname}
  User ${user}
  IdentityFile ${IdentityFile}
'@