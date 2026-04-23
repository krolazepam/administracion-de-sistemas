$DC_PATH = "DC=empresa,DC=local"

function Rol1-AdminIdentidad {
    Print-Info "Configurando Rol 1: admin_identidad..."

    foreach ($ou in @("Cuates", "NoCuates")) {
        $path = "OU=$ou,$DC_PATH"

        # Crear usuarios
        dsacls $path /G "EMPRESA\admin_identidad:CC;user" | Out-Null

        # Eliminar usuarios
        dsacls $path /G "EMPRESA\admin_identidad:DC;user" | Out-Null

        # Modificar atributos (telefono, oficina, correo)
        dsacls $path /G "EMPRESA\admin_identidad:WP" /I:S | Out-Null

        # Resetear contrasena
        dsacls $path /G "EMPRESA\admin_identidad:CA;Reset Password;user" /I:S | Out-Null

        # Desbloquear cuentas
        dsacls $path /G "EMPRESA\admin_identidad:WP;lockoutTime;user" /I:S | Out-Null

        Print-Ok "  Permisos aplicados en OU: $ou"
    }

    Print-Ok "Rol 1 (admin_identidad) configurado."
}


function Rol2-AdminStorage {
    Print-Info "Configurando Rol 2: admin_storage..."

    # RESTRICCION: Denegar Reset Password en ambas OUs
    foreach ($ou in @("Cuates", "NoCuates")) {
        $path = "OU=$ou,$DC_PATH"
        dsacls $path /D "EMPRESA\admin_storage:CA;Reset Password;user" /I:S | Out-Null
        Print-Ok "  Reset Password DENEGADO en OU: $ou"
    }

    # Lectura en AD
    dsacls $DC_PATH /G "EMPRESA\admin_storage:GR" /I:S | Out-Null

    # Administrador local para usar FSRM
    net localgroup "Administradores" "EMPRESA\admin_storage" /add 2>$null | Out-Null
    Print-Ok "  admin_storage agregado a Administradores locales (FSRM)."

    # Crear estructura FSRM base
    Print-Info "  Creando estructura FSRM base..."

    if (-not (Test-Path "C:\Perfiles")) {
        New-Item -Path "C:\Perfiles" -ItemType Directory -Force | Out-Null
        Print-Ok "  Carpeta C:\Perfiles creada."
    }

    $tmpl = Get-FsrmQuotaTemplate -Name "Cuota-100MB" -ErrorAction SilentlyContinue
    if (-not $tmpl) {
        New-FsrmQuotaTemplate -Name "Cuota-100MB" -Size 100MB | Out-Null
        Print-Ok "  Plantilla Cuota-100MB creada."
    }

    $quota = Get-FsrmQuota -Path "C:\Perfiles" -ErrorAction SilentlyContinue
    if (-not $quota) {
        New-FsrmQuota -Path "C:\Perfiles" -Size 100MB | Out-Null
        Print-Ok "  Cuota 100MB aplicada en C:\Perfiles."
    }

    $fg = Get-FsrmFileGroup -Name "Archivos-Prohibidos" -ErrorAction SilentlyContinue
    if (-not $fg) {
        New-FsrmFileGroup -Name "Archivos-Prohibidos" -IncludePattern @("*.mp3","*.mp4","*.exe","*.avi","*.mkv") | Out-Null
        Print-Ok "  Grupo Archivos-Prohibidos creado."
    }

    $fst = Get-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -ErrorAction SilentlyContinue
    if (-not $fst) {
        New-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -Active -IncludeGroup @("Archivos-Prohibidos") | Out-Null
        Print-Ok "  Plantilla Pantalla-Prohibidos creada."
    }

    $fs = Get-FsrmFileScreen -Path "C:\Perfiles" -ErrorAction SilentlyContinue
    if (-not $fs) {
        New-FsrmFileScreen -Path "C:\Perfiles" -Template "Pantalla-Prohibidos" | Out-Null
        Print-Ok "  Apantallamiento aplicado en C:\Perfiles."
    }

    Print-Ok "Rol 2 (admin_storage) configurado."
}


function Rol3-AdminPoliticas {
    Print-Info "Configurando Rol 3: admin_politicas..."

    # Solo lectura en todo el dominio
    dsacls $DC_PATH /G "EMPRESA\admin_politicas:GR" /I:S | Out-Null

    Print-Ok "  Lectura en todo el dominio aplicada."
    Print-Ok "Rol 3 (admin_politicas) configurado."
}


function Rol4-AdminAuditoria {
    Print-Info "Configurando Rol 4: admin_auditoria..."

    dsacls $DC_PATH /G "EMPRESA\admin_auditoria:GR" /I:S | Out-Null

    net localgroup "Administradores" "EMPRESA\admin_auditoria" /add 2>$null | Out-Null
    Print-Ok "  admin_auditoria agregado a Administradores locales (auditpol)."

    net localgroup "Lectores del registro de eventos" "EMPRESA\admin_auditoria" /add 2>$null | Out-Null
    Print-Ok "  admin_auditoria agregado a Lectores del registro de eventos."

    Print-Ok "Rol 4 (admin_auditoria) configurado."
}


function Configurar-Delegacion {
    Clear-Host
    Write-Host "========== Configuracion de Delegacion RBAC =========="
    Write-Host ""

    Rol1-AdminIdentidad
    Write-Host ""
    Rol2-AdminStorage
    Write-Host ""
    Rol3-AdminPoliticas
    Write-Host ""
    Rol4-AdminAuditoria

    Write-Host ""
    Print-Ok "Delegacion RBAC configurada correctamente."
    Write-Host ""
    Write-Host "Resumen:"
    Write-Host "  admin_identidad -> Cuates/NoCuates: Crear/Eliminar/Modificar/Reset/Desbloquear" -ForegroundColor White
    Write-Host "  admin_storage   -> Cuates/NoCuates: Reset DENEGADO + FSRM habilitado" -ForegroundColor White
    Write-Host "  admin_politicas -> Todo el dominio: Solo lectura" -ForegroundColor White
    Write-Host "  admin_auditoria -> Todo el dominio: Solo lectura + Logs de seguridad" -ForegroundColor White
    Write-Host ""
}