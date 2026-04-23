$DOMINIO      = "empresa.local"
$DC_PATH      = "DC=empresa,DC=local"
$CSV_USUARIOS = "$PSScriptRoot\usuarios_p9.csv"

$ADMINS = @(
    [PSCustomObject]@{ Sam = "admin_identidad"; Nombre = "Admin"; Apellido = "Identidad"; Password = "Admin@Identidad123" },
    [PSCustomObject]@{ Sam = "admin_storage";   Nombre = "Admin"; Apellido = "Storage";   Password = "Admin@Storage123"   },
    [PSCustomObject]@{ Sam = "admin_politicas"; Nombre = "Admin"; Apellido = "Politicas"; Password = "Admin@Politicas123" },
    [PSCustomObject]@{ Sam = "admin_auditoria"; Nombre = "Admin"; Apellido = "Auditoria"; Password = "Admin@Auditoria123" }
)

function Inicializar-Entorno {
    Write-Host ""
    Write-Host "========== Inicializar Entorno =========="

    # Instalar AD
    $rol = Get-WindowsFeature -Name AD-Domain-Services
    if ($rol.InstallState -ne "Installed") {
        Print-Info "Instalando rol AD-Domain-Services..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Print-Ok "Rol AD instalado."
    } else {
        Print-Warn "AD-Domain-Services ya instalado (se omite)."
    }

    # Instalar FSRM (necesario para Rol 2: admin_storage)
    $fsrm = Get-WindowsFeature -Name FS-Resource-Manager
    if ($fsrm.InstallState -ne "Installed") {
        Print-Info "Instalando FSRM (File Server Resource Manager)..."
        Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
        Print-Ok "FSRM instalado."
    } else {
        Print-Warn "FSRM ya instalado (se omite)."
    }

    # Promover a DC
    $domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
    if ($domainRole -ge 4) {
        Print-Warn "Ya es Controlador de Dominio (se omite promocion)."
        return
    }

    Print-Info "Promoviendo a Controlador de Dominio..."
    $safePass = ConvertTo-SecureString "SafeMode@Pass123!" -AsPlainText -Force

    Install-ADDSForest `
        -DomainName                    $DOMINIO `
        -DomainNetBiosName             "EMPRESA" `
        -InstallDns `
        -SafeModeAdministratorPassword $safePass `
        -Force

    Print-Warn "El servidor se reiniciara. Ejecuta el script de nuevo y elige opcion 2."
}

function Crear-OUs {
    Print-Info "Verificando Unidades Organizativas..."
    foreach ($ou in @("Admins", "Cuates", "NoCuates")) {
        $existe = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            New-ADOrganizationalUnit -Name $ou -Path $DC_PATH
            Print-Ok "OU creada: $ou"
        } else {
            Print-Warn "OU ya existe: $ou (se omite)"
        }
    }
}

function Crear-Admins {
    Print-Info "Verificando usuarios administradores delegados..."
    foreach ($admin in $ADMINS) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($admin.Sam)'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            $pass = ConvertTo-SecureString $admin.Password -AsPlainText -Force
            New-ADUser `
                -Name              "$($admin.Nombre) $($admin.Apellido)" `
                -GivenName         $admin.Nombre `
                -Surname           $admin.Apellido `
                -SamAccountName    $admin.Sam `
                -UserPrincipalName "$($admin.Sam)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              "OU=Admins,$DC_PATH" `
                -Enabled           $true
            Print-Ok "Admin creado: $($admin.Sam) / $($admin.Password)"
        } else {
            Print-Warn "Admin ya existe: $($admin.Sam) (se omite)"
        }
    }
}

function Crear-UsuariosCSV {
    if (-not (Test-Path $CSV_USUARIOS)) {
        Print-Err "No se encontro el CSV: $CSV_USUARIOS"
        return
    }

    $usuarios = Import-Csv $CSV_USUARIOS
    $creados  = 0
    $omitidos = 0

    Print-Info "Leyendo CSV: $($usuarios.Count) usuario(s)..."
    Write-Host ""

    foreach ($u in $usuarios) {
        if ($u.OU -notin @("Cuates", "NoCuates")) {
            Print-Warn "OU invalida '$($u.OU)' para '$($u.Usuario)'. Solo Cuates o NoCuates."
            $omitidos++
            continue
        }
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Usuario)'" -ErrorAction SilentlyContinue
        if (-not $existe) {
            $pass   = ConvertTo-SecureString $u.Contrasena -AsPlainText -Force
            New-ADUser `
                -Name              "$($u.Nombre) $($u.Apellido)" `
                -GivenName         $u.Nombre `
                -Surname           $u.Apellido `
                -SamAccountName    $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              "OU=$($u.OU),$DC_PATH" `
                -Enabled           $true
            Print-Ok "Creado: $($u.Usuario) -> $($u.OU)"
            $creados++
        } else {
            Print-Warn "Ya existe: $($u.Usuario) (se omite)"
            $omitidos++
        }
    }

    Write-Host ""
    Print-Info "Resumen: $creados creado(s), $omitidos omitido(s)."
}

function Configurar-AD {
    Clear-Host
    Write-Host "========== Configuracion de Active Directory =========="
    Write-Host ""

    Crear-OUs
    Write-Host ""
    Crear-Admins
    Write-Host ""
    Crear-UsuariosCSV

    Write-Host ""
    Print-Ok "Active Directory configurado correctamente."
    Write-Host ""
}
