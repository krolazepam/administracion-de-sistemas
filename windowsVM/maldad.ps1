$usuarios = @("notlizy","netobrdf","amora","lvega","dulcevrz","sinji","asuka","dazai","yurio","mob","sdiaz","cpena","dualyrf","dulceosu","hosuna","nanami","langa","ash","kaori","tanjiro")

foreach ($u in $usuarios) {
    $ruta = "C:\Perfiles\$u"
    $acl  = Get-Acl $ruta
    $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "EMPRESA\$u", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($regla)
    Set-Acl -Path $ruta -AclObject $acl
    Write-Host "[OK] Permisos aplicados: $u" -ForegroundColor Green
}