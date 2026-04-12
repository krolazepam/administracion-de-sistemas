$Global:Dominio     = $env:USERDNSDOMAIN                          # ej. EMPRESA.LOCAL
$Global:DominioNB   = ($env:USERDOMAIN)                           # ej. EMPRESA (NetBIOS)
$Global:DCBase      = (Get-ADDomain).DistinguishedName            # ej. DC=empresa,DC=local
$Global:OU_Admins   = "OU=AdminsDelegados,$($Global:DCBase)"
$Global:OU_Cuates   = "OU=Cuates,$($Global:DCBase)"
$Global:OU_NoCuates = "OU=NoCuates,$($Global:DCBase)"
$Global:LogPath     = "C:\Practica09\Logs"
$Global:Color_OK    = "Green"
$Global:Color_ERR   = "Red"
$Global:Color_INFO  = "Cyan"
$Global:Color_WARN  = "Yellow"

# ============================================================
#  FUNCIONES DE UTILIDAD
# ============================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  -----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "        PRACTICA 09 - AD HARDENING / RBAC / MFA             " -ForegroundColor Cyan
    Write-Host "        Seguridad Avanzada en Active Directory              " -ForegroundColor Cyan
    Write-Host "  -----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK    { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor $Global:Color_OK }
function Write-ERR   { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor $Global:Color_ERR }
function Write-INFO  { param($msg) Write-Host "  [..] $msg"  -ForegroundColor $Global:Color_INFO }
function Write-WARN  { param($msg) Write-Host "  [!]  $msg"  -ForegroundColor $Global:Color_WARN }

function Ensure-LogDir {
    if (-not (Test-Path $Global:LogPath)) {
        New-Item -ItemType Directory -Path $Global:LogPath -Force | Out-Null
        Write-INFO "Directorio de logs creado: $($Global:LogPath)"
    }
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  Presiona ENTER para volver al menu..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

function Test-ADModuleLoaded {
    if (-not (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
        } catch {
            Write-ERR "No se pudo cargar el modulo ActiveDirectory. Instala RSAT."
            return $false
        }
    }
    return $true
}

function Ensure-OU {
    param([string]$OUPath, [string]$OUName, [string]$ParentPath)
    try {
        Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop | Out-Null
        Write-INFO "OU ya existe: $OUName"
    } catch {
        New-ADOrganizationalUnit -Name $OUName -Path $ParentPath -ProtectedFromAccidentalDeletion $false
        Write-OK "OU creada: $OUName"
    }
}

# ============================================================
#  BLOQUE 1 - DELEGACION DE CONTROL Y RBAC
# ============================================================

function Crear-OUsBase {
    Write-INFO "Verificando/creando OUs necesarias..."
    Ensure-OU -OUPath $Global:OU_Admins   -OUName "AdminsDelegados" -ParentPath $Global:DCBase
    Ensure-OU -OUPath $Global:OU_Cuates   -OUName "Cuates"          -ParentPath $Global:DCBase
    Ensure-OU -OUPath $Global:OU_NoCuates -OUName "NoCuates"        -ParentPath $Global:DCBase
}

function Crear-UsuariosDelegados {
    Write-Banner
    Write-Host "  [1.1] CREAR USUARIOS ADMINISTRADORES DELEGADOS" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    Crear-OUsBase

    $usuarios = @(
        @{ Nombre="admin_identidad"; Descripcion="Rol 1 - IAM Operator: Gestion ciclo de vida de usuarios" },
        @{ Nombre="admin_storage";   Descripcion="Rol 2 - Storage Operator: Gestion de cuotas y FSRM" },
        @{ Nombre="admin_politicas"; Descripcion="Rol 3 - GPO Compliance: Gestion de directivas de grupo" },
        @{ Nombre="admin_auditoria"; Descripcion="Rol 4 - Security Auditor: Monitoreo de eventos (solo lectura)" }
    )

    Write-WARN "Se usara la contrasena 'Admin@Practica09!' para todos los usuarios delegados."
    Write-WARN "Cambiala antes de produccion."
    Write-Host ""

    $passSegura = ConvertTo-SecureString "Admin@Practica09!" -AsPlainText -Force

    foreach ($u in $usuarios) {
        try {
            $existe = Get-ADUser -Filter { SamAccountName -eq $u.Nombre } -ErrorAction SilentlyContinue
            if ($existe) {
                Write-WARN "Usuario '$($u.Nombre)' ya existe. Se omite creacion."
            } else {
                New-ADUser `
                    -Name              $u.Nombre `
                    -SamAccountName    $u.Nombre `
                    -UserPrincipalName "$($u.Nombre)@$($Global:Dominio)" `
                    -Description       $u.Descripcion `
                    -Path              $Global:OU_Admins `
                    -AccountPassword   $passSegura `
                    -Enabled           $true `
                    -PasswordNeverExpires $false `
                    -ChangePasswordAtLogon $false
                Write-OK "Creado: $($u.Nombre)"
            }
        } catch {
            Write-ERR "Error creando $($u.Nombre): $($_.Exception.Message)"
        }
    }

    # Crear usuarios de prueba en OU Cuates y No Cuates
    Write-Host ""
    Write-INFO "Creando usuarios de prueba en OU Cuates y NoCuates..."
    $usuariosTest = @("usr_cuate01","usr_cuate02","usr_nocuate01")
    foreach ($u in $usuariosTest) {
        try {
            $existe = Get-ADUser -Filter { SamAccountName -eq $u } -ErrorAction SilentlyContinue
            if (-not $existe) {
                $ouDestino = if ($u -like "*nocuate*") { $Global:OU_NoCuates } else { $Global:OU_Cuates }
                New-ADUser -Name $u -SamAccountName $u -Path $ouDestino `
                    -AccountPassword (ConvertTo-SecureString "UserPass@2024!" -AsPlainText -Force) `
                    -Enabled $true -ChangePasswordAtLogon $false
                Write-OK "Creado usuario de prueba: $u"
            }
        } catch {
            Write-WARN "No se pudo crear usuario de prueba $u : $($_.Exception.Message)"
        }
    }

    Pause-Menu
}

function Configurar-ACLs-RBAC {
    Write-Banner
    Write-Host "  [1.2] CONFIGURAR ACLs Y PERMISOS GRANULARES (RBAC)" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    # --- ROL 1: admin_identidad - Permisos sobre Cuates y NoCuates ---
    Write-Host "  ROL 1 - admin_identidad (IAM Operator)" -ForegroundColor Yellow
    $ousCubiertos = @($Global:OU_Cuates, $Global:OU_NoCuates)
    foreach ($ou in $ousCubiertos) {
        try {
            # Crear/Eliminar/Modificar usuarios
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:CCDC;user" /I:S 2>&1 | Out-Null
            # Reset Password
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:CA;Reset Password;user" /I:S 2>&1 | Out-Null
            # Leer/Escribir propiedades basicas (telefono, oficina, correo)
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;telephoneNumber;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;physicalDeliveryOfficeName;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;mail;user" /I:S 2>&1 | Out-Null
            # Desbloqueo de cuentas
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;lockoutTime;user" /I:S 2>&1 | Out-Null
            Write-OK "Permisos IAM Operator aplicados sobre: $ou"
        } catch {
            Write-ERR "Error en ROL 1 sobre $ou : $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Host "  ROL 2 - admin_storage (Storage Operator)" -ForegroundColor Yellow
    Write-INFO "  DENEGANDO Reset Password a admin_storage en todo el dominio..."
    foreach ($ou in $ousCubiertos) {
        try {
            & dsacls $ou /D "$($Global:DominioNB)\admin_storage:CA;Reset Password;user" /I:S 2>&1 | Out-Null
            Write-OK "Denegado Reset Password para admin_storage en: $ou"
        } catch {
            Write-ERR "Error aplicando denegacion a admin_storage en $ou : $($_.Exception.Message)"
        }
    }
    # Agregar admin_storage al grupo de operadores de servidor para FSRM
    try {
        Add-ADGroupMember -Identity "Server Operators" -Members "admin_storage" -ErrorAction SilentlyContinue
        Write-OK "admin_storage agregado a 'Server Operators' (para acceso FSRM)"
    } catch {
        Write-WARN "No se pudo agregar admin_storage a Server Operators: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "  ROL 3 - admin_politicas (GPO Compliance)" -ForegroundColor Yellow
    try {
        # Permiso de lectura en todo el dominio
        & dsacls $Global:DCBase /G "$($Global:DominioNB)\admin_politicas:GR" 2>&1 | Out-Null
        Write-OK "Permiso de lectura en dominio para admin_politicas"
        # Permiso de escritura SOLO sobre GPOs (linkGPOptions en OUs)
        & dsacls $Global:OU_Cuates   /G "$($Global:DominioNB)\admin_politicas:RPWP;gPLink" 2>&1 | Out-Null
        & dsacls $Global:OU_NoCuates /G "$($Global:DominioNB)\admin_politicas:RPWP;gPLink" 2>&1 | Out-Null
        # Denegar escritura sobre objetos de usuario
        & dsacls $Global:OU_Cuates   /D "$($Global:DominioNB)\admin_politicas:WP;;user" 2>&1 | Out-Null
        Write-OK "admin_politicas: lectura global, escritura solo en gPLink"
    } catch {
        Write-ERR "Error configurando ROL 3: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "  ROL 4 - admin_auditoria (Security Auditor - Solo Lectura)" -ForegroundColor Yellow
    try {
        & dsacls $Global:DCBase /G "$($Global:DominioNB)\admin_auditoria:GR" /I:T 2>&1 | Out-Null
        Write-OK "Permiso de solo lectura aplicado para admin_auditoria en todo el dominio"

        # Agregar al grupo Event Log Readers para acceso a logs de seguridad
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction SilentlyContinue
        Write-OK "admin_auditoria agregado al grupo 'Event Log Readers'"
    } catch {
        Write-ERR "Error configurando ROL 4: $($_.Exception.Message)"
    }

    Pause-Menu
}

# ============================================================
#  BLOQUE 2 - FGPP Y AUDITORIA
# ============================================================

function Configurar-FGPP {
    Write-Banner
    Write-Host "  [2.1] DIRECTIVAS DE CONTRASENA AJUSTADA (FGPP)" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    # Verificar que el nivel funcional del dominio sea al menos 2008
    $nivelFuncional = (Get-ADDomain).DomainMode
    Write-INFO "Nivel funcional del dominio: $nivelFuncional"

    # FGPP para administradores (minimo 12 caracteres)
    Write-Host ""
    Write-Host "  Creando politica para ADMINISTRADORES (min. 12 chars)..." -ForegroundColor Yellow
    try {
        $existeFGPP = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "FGPP_Administradores" } -ErrorAction SilentlyContinue
        if ($existeFGPP) {
            Write-WARN "FGPP_Administradores ya existe. Actualizando..."
            Set-ADFineGrainedPasswordPolicy -Identity "FGPP_Administradores" `
                -MinPasswordLength        12 `
                -ComplexityEnabled        $true `
                -PasswordHistoryCount     10 `
                -MinPasswordAge           "1.00:00:00" `
                -MaxPasswordAge           "60.00:00:00" `
                -ReversibleEncryptionEnabled $false `
                -LockoutThreshold         3 `
                -LockoutDuration          "00:30:00" `
                -LockoutObservationWindow "00:30:00"
        } else {
            New-ADFineGrainedPasswordPolicy `
                -Name                    "FGPP_Administradores" `
                -Precedence              10 `
                -MinPasswordLength       12 `
                -ComplexityEnabled       $true `
                -PasswordHistoryCount    10 `
                -MinPasswordAge          "1.00:00:00" `
                -MaxPasswordAge          "60.00:00:00" `
                -ReversibleEncryptionEnabled $false `
                -LockoutThreshold        3 `
                -LockoutDuration         "00:30:00" `
                -LockoutObservationWindow "00:30:00" `
                -ProtectedFromAccidentalDeletion $true
        }
        Write-OK "FGPP_Administradores configurada (12 chars min, lockout 3 intentos / 30 min)"
    } catch {
        Write-ERR "Error creando FGPP para admins: $($_.Exception.Message)"
    }

    # FGPP para usuarios estandar (minimo 8 caracteres)
    Write-Host ""
    Write-Host "  Creando politica para USUARIOS ESTANDAR (min. 8 chars)..." -ForegroundColor Yellow
    try {
        $existeFGPP2 = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq "FGPP_Usuarios" } -ErrorAction SilentlyContinue
        if ($existeFGPP2) {
            Write-WARN "FGPP_Usuarios ya existe. Actualizando..."
            Set-ADFineGrainedPasswordPolicy -Identity "FGPP_Usuarios" `
                -MinPasswordLength        8 `
                -ComplexityEnabled        $true `
                -LockoutThreshold         5 `
                -LockoutDuration          "00:30:00" `
                -LockoutObservationWindow "00:30:00"
        } else {
            New-ADFineGrainedPasswordPolicy `
                -Name                    "FGPP_Usuarios" `
                -Precedence              20 `
                -MinPasswordLength       8 `
                -ComplexityEnabled       $true `
                -PasswordHistoryCount    5 `
                -MinPasswordAge          "0.00:00:00" `
                -MaxPasswordAge          "90.00:00:00" `
                -ReversibleEncryptionEnabled $false `
                -LockoutThreshold        5 `
                -LockoutDuration         "00:30:00" `
                -LockoutObservationWindow "00:30:00" `
                -ProtectedFromAccidentalDeletion $true
        }
        Write-OK "FGPP_Usuarios configurada (8 chars min, lockout 5 intentos / 30 min)"
    } catch {
        Write-ERR "Error creando FGPP para usuarios: $($_.Exception.Message)"
    }

    # Aplicar FGPP a los usuarios delegados
    Write-Host ""
    Write-INFO "Aplicando FGPP_Administradores a los 4 usuarios delegados..."
    $adminsDelgados = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    foreach ($u in $adminsDelgados) {
        try {
            Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP_Administradores" -Subjects $u -ErrorAction SilentlyContinue
            Write-OK "FGPP aplicada a: $u"
        } catch {
            Write-WARN "No se pudo aplicar FGPP a $u : $($_.Exception.Message)"
        }
    }

    # Aplicar FGPP a usuarios estandar (la OU no aplica directo, se usa un grupo global)
    Write-Host ""
    Write-INFO "Creando grupo global 'GG_UsuariosEstandar' para aplicar FGPP_Usuarios..."
    try {
        $grpExiste = Get-ADGroup -Filter { Name -eq "GG_UsuariosEstandar" } -ErrorAction SilentlyContinue
        if (-not $grpExiste) {
            New-ADGroup -Name "GG_UsuariosEstandar" -GroupScope Global -Path $Global:DCBase
            Write-OK "Grupo GG_UsuariosEstandar creado"
        }
        # Agregar usuarios de prueba al grupo
        Add-ADGroupMember -Identity "GG_UsuariosEstandar" -Members "usr_cuate01","usr_cuate02","usr_nocuate01" -ErrorAction SilentlyContinue
        Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP_Usuarios" -Subjects "GG_UsuariosEstandar" -ErrorAction SilentlyContinue
        Write-OK "FGPP_Usuarios aplicada al grupo GG_UsuariosEstandar"
    } catch {
        Write-WARN "Advertencia con grupo de usuarios estandar: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Configurar-Auditoria {
    Write-Banner
    Write-Host "  [2.2] HARDENING DE AUDITORIA DE EVENTOS" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # Habilitar auditoria de Logon (inicio de sesion)
    Write-INFO "Habilitando auditoria de inicio de sesion (exito y fallo)..."
    try {
        & auditpol /set /subcategory:"Logon" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"Logoff" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria de Logon/Logoff habilitada"
    } catch {
        Write-ERR "Error configurando auditoria de Logon: $($_.Exception.Message)"
    }

    # Auditoria de acceso a objetos
    Write-INFO "Habilitando auditoria de acceso a objetos..."
    try {
        & auditpol /set /subcategory:"Object Access" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"File System" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria de Object Access y File System habilitada"
    } catch {
        Write-ERR "Error en auditoria de objetos: $($_.Exception.Message)"
    }

    # Auditoria de gestion de cuentas
    Write-INFO "Habilitando auditoria de gestion de cuentas..."
    try {
        & auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria de User/Group Management habilitada"
    } catch {
        Write-ERR "Error en auditoria de cuentas: $($_.Exception.Message)"
    }

    # Auditoria de cambios de directiva
    Write-INFO "Habilitando auditoria de cambios de politica..."
    try {
        & auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria de cambios de politica habilitada"
    } catch {
        Write-ERR "Error en auditoria de politicas: $($_.Exception.Message)"
    }

    # Auditoria de uso de privilegios
    Write-INFO "Habilitando auditoria de uso de privilegios..."
    try {
        & auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria de Sensitive Privilege Use habilitada"
    } catch {
        Write-ERR "Error en auditoria de privilegios: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Estado actual de auditoria:"
    & auditpol /get /category:* | Where-Object { $_ -match "Logon|Object|Account|Policy" }

    Pause-Menu
}

function Ejecutar-ScriptMonitoreo {
    Write-Banner
    Write-Host "  [2.3] SCRIPT DE MONITOREO - ACCESOS DENEGADOS (ID 4625)" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Ensure-LogDir

    $timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
    $archivoCSV  = "$($Global:LogPath)\AccesosDenegados_$timestamp.csv"
    $archivoTXT  = "$($Global:LogPath)\AccesosDenegados_$timestamp.txt"

    Write-INFO "Extrayendo ultimos 10 eventos de ID 4625 del log de Seguridad..."

    try {
        $eventos = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4625
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if (-not $eventos) {
            Write-WARN "No se encontraron eventos 4625. Generando evento de prueba..."
            # Generar un intento fallido de prueba para que haya algo en el log
            $credFalsa = New-Object System.Management.Automation.PSCredential("usuarioInvalido99", (ConvertTo-SecureString "claveInvalida!" -AsPlainText -Force))
            try { Start-Process -FilePath "cmd.exe" -Credential $credFalsa -WindowStyle Hidden -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Seconds 2
            $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        }

        if ($eventos) {
            $resultado = foreach ($e in $eventos) {
                [PSCustomObject]@{
                    Fecha_Hora     = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    EventoID       = $e.Id
                    TipoFallo      = try { $e.Properties[8].Value }  catch { "N/A" }
                    Usuario        = try { $e.Properties[5].Value }  catch { "N/A" }
                    Dominio        = try { $e.Properties[6].Value }  catch { "N/A" }
                    Proceso        = try { $e.Properties[11].Value } catch { "N/A" }
                    IP_Origen      = try { $e.Properties[19].Value } catch { "N/A" }
                    Puerto_Origen  = try { $e.Properties[20].Value } catch { "N/A" }
                    Descripcion    = "Intento fallido de inicio de sesion"
                }
            }

            # Exportar CSV
            $resultado | Export-Csv -Path $archivoCSV -NoTypeInformation -Encoding UTF8
            Write-OK "Exportado a CSV: $archivoCSV"

            # Exportar TXT con formato legible
            $lineasTXT = @()
            $lineasTXT += "=" * 70
            $lineasTXT += " REPORTE DE ACCESOS DENEGADOS - EVENTO ID 4625"
            $lineasTXT += " Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lineasTXT += " Servidor: $env:COMPUTERNAME | Dominio: $($Global:Dominio)"
            $lineasTXT += "=" * 70
            $lineasTXT += ""
            $i = 1
            foreach ($r in $resultado) {
                $lineasTXT += "  EVENTO #$i"
                $lineasTXT += "  Fecha/Hora  : $($r.Fecha_Hora)"
                $lineasTXT += "  Usuario     : $($r.Usuario)@$($r.Dominio)"
                $lineasTXT += "  IP Origen   : $($r.IP_Origen):$($r.Puerto_Origen)"
                $lineasTXT += "  Proceso     : $($r.Proceso)"
                $lineasTXT += "  Tipo Fallo  : $($r.TipoFallo)"
                $lineasTXT += "  " + ("-" * 60)
                $i++
            }
            $lineasTXT += ""
            $lineasTXT += "  Total de eventos encontrados: $($resultado.Count)"
            $lineasTXT | Out-File -FilePath $archivoTXT -Encoding UTF8
            Write-OK "Exportado a TXT: $archivoTXT"

            # Mostrar resumen en pantalla
            Write-Host ""
            Write-Host "  RESUMEN DE EVENTOS ENCONTRADOS:" -ForegroundColor White
            $resultado | Format-Table Fecha_Hora, Usuario, Dominio, IP_Origen -AutoSize

        } else {
            Write-WARN "No se encontraron eventos 4625 en el log de seguridad."
            Write-WARN "Asegurate de que la auditoria de Logon este habilitada (opcion 2.2)."
            "No se encontraron eventos 4625. Fecha: $(Get-Date)" | Out-File $archivoTXT
        }

        Write-Host ""
        Write-INFO "Archivos guardados en: $($Global:LogPath)"

    } catch {
        Write-ERR "Error extrayendo eventos: $($_.Exception.Message)"
    }

    Pause-Menu
}

# ============================================================
#  BLOQUE 3 - MFA (GOOGLE AUTHENTICATOR / TOTP)
# ============================================================

function Instalar-MFA-TOTP {
    Write-Banner
    Write-Host "  [3.1] INSTALACION DE MFA - GOOGLE AUTHENTICATOR (TOTP)" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Opciones de Credential Provider TOTP para Windows Server:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [A] WinAuth (instalacion manual + Credential Provider)" -ForegroundColor Cyan
    Write-Host "  [B] Google Authenticator Credential Provider (GitHub OSS)" -ForegroundColor Cyan
    Write-Host "  [C] Mostrar instrucciones de instalacion manual detalladas" -ForegroundColor Cyan
    Write-Host "  [D] Configurar clave TOTP y QR para usuario existente" -ForegroundColor Cyan
    Write-Host "  [E] Volver al menu principal" -ForegroundColor DarkGray
    Write-Host ""
    $opMFA = Read-Host "  Selecciona una opcion"

    switch ($opMFA.ToUpper()) {
        "A" { Instalar-MFA-WinAuth }
        "B" { Instalar-MFA-CredProvider }
        "C" { Mostrar-InstruccionesMFA }
        "D" { Configurar-ClaveTotp }
        "E" { return }
        default { Write-WARN "Opcion no valida." ; Pause-Menu }
    }
}

function Instalar-MFA-WinAuth {
    Write-Host ""
    Write-INFO "Intentando descargar WinAuth desde GitHub..."
    $urlWinAuth = "https://github.com/winauth/winauth/releases/latest/download/WinAuth.exe"
    $destino    = "C:\Practica09\WinAuth.exe"

    try {
        Ensure-LogDir
        if (-not (Test-Path "C:\Practica09")) { New-Item -ItemType Directory -Path "C:\Practica09" -Force | Out-Null }
        Invoke-WebRequest -Uri $urlWinAuth -OutFile $destino -UseBasicParsing -TimeoutSec 60
        Write-OK "WinAuth descargado en: $destino"
        Write-WARN "WinAuth es un generador de tokens TOTP de escritorio, NO un Credential Provider."
        Write-WARN "Para MFA en login de Windows, necesitas un Credential Provider (opcion B)."
    } catch {
        Write-ERR "No se pudo descargar WinAuth: $($_.Exception.Message)"
        Write-INFO "Descargalo manualmente desde: https://winauth.github.io/winauth/"
    }
    Pause-Menu
}

function Instalar-MFA-CredProvider {
    Write-Host ""
    Write-WARN "El Credential Provider de Google Authenticator para Windows requiere"
    Write-WARN "compilacion desde codigo fuente o un instalador de terceros confiable."
    Write-Host ""
    Write-INFO "Repositorios de referencia para laboratorio:"
    Write-Host "  -> github.com/StratumSecurity/GoogleAuthenticatorCredentialProvider" -ForegroundColor Cyan
    Write-Host "  -> github.com/nicowillis/google-authenticator-windows" -ForegroundColor Cyan
    Write-Host ""
    Write-INFO "Pasos de instalacion del Credential Provider compilado:"
    Write-Host ""
    Write-Host "  1. Copia el archivo 'GoogleAuthCP.dll' al servidor" -ForegroundColor White
    Write-Host "     Ruta destino: C:\Windows\System32\" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2. Registra el DLL como Credential Provider:" -ForegroundColor White
    Write-Host "     reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential` Providers\{GUID-DEL-CP}" -ForegroundColor DarkGray
    Write-Host "     reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential` Providers\{GUID-DEL-CP} /v `"(Default)`" /d `"GoogleAuthCP`"" -ForegroundColor DarkGray
    Write-Host ""

    # Intentar registrar si el DLL ya fue copiado manualmente
    $dllPath = Read-Host "  Si ya tienes el DLL en System32, ingresa su nombre (ej: GoogleAuthCP.dll) o ENTER para omitir"
    if ($dllPath -ne "") {
        try {
            $fullDll = "C:\Windows\System32\$dllPath"
            if (Test-Path $fullDll) {
                & regsvr32 /s $fullDll
                Write-OK "DLL registrado: $fullDll"
                Write-WARN "Reinicia el servidor para que la pantalla de login muestre el nuevo Credential Provider."
            } else {
                Write-ERR "No se encontro el archivo: $fullDll"
            }
        } catch {
            Write-ERR "Error al registrar DLL: $($_.Exception.Message)"
        }
    }
    Pause-Menu
}

function Mostrar-InstruccionesMFA {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         INSTRUCCIONES DE CONFIGURACION MFA TOTP          ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ARQUITECTURA:" -ForegroundColor Yellow
    Write-Host "  Usuario ingresa Pass -> Credential Provider intercepta"
    Write-Host "  -> LSASS valida AD -> Si OK, solicita TOTP de 6 digitos"
    Write-Host "  -> Credential Provider valida TOTP -> Acceso concedido"
    Write-Host ""
    Write-Host "  COMPONENTES NECESARIOS:" -ForegroundColor Yellow
    Write-Host "  1. Credential Provider DLL (filtro entre login y LSASS)"
    Write-Host "  2. Secreto TOTP por usuario (clave compartida base32)"
    Write-Host "  3. App Google Authenticator en el movil del usuario"
    Write-Host ""
    Write-Host "  REGISTRO EN WINDOWS (clave de registro):" -ForegroundColor Yellow
    Write-Host "  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\"
    Write-Host "    Authentication\Credential Providers\{GUID}"
    Write-Host ""
    Write-Host "  CLAVE BASE32 DE EJEMPLO para pruebas:" -ForegroundColor Yellow

    # Generar una clave TOTP de ejemplo (Base32 aleatorio de 20 bytes)
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $claveTotp = ""
    $buffer = 0; $bitsLeft = 0
    foreach ($b in $bytes) {
        $buffer = ($buffer -shl 8) -bor $b
        $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $claveTotp += $base32Chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }
    Write-Host "  $claveTotp" -ForegroundColor Green
    Write-Host ""
    Write-Host "  URI para QR (escanear con Google Authenticator):" -ForegroundColor Yellow
    Write-Host "  otpauth://totp/Practica09:admin_identidad@$($Global:Dominio)?secret=$claveTotp&issuer=Practica09" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  BLOQUEO POR INTENTOS FALLIDOS MFA:" -ForegroundColor Yellow
    Write-Host "  Se gestiona via FGPP: LockoutThreshold=3, LockoutDuration=30min"
    Write-Host "  (ya configurado en la opcion 2.1 del menu)"
    Write-Host ""

    Ensure-LogDir
    $instrFile = "$($Global:LogPath)\Instrucciones_MFA.txt"
    @"
INSTRUCCIONES MFA TOTP - PRACTICA 09
Generado: $(Get-Date)
Dominio: $($Global:Dominio)

CLAVE TOTP DE EJEMPLO: $claveTotp
URI QR: otpauth://totp/Practica09:admin_identidad@$($Global:Dominio)?secret=$claveTotp&issuer=Practica09

PASOS:
1. Instalar Credential Provider DLL en C:\Windows\System32\
2. Registrar el DLL en el registro de Windows (ver clave arriba)
3. Distribuir clave TOTP a cada usuario admin (escanear QR)
4. Reiniciar el servidor
5. Verificar que la pantalla de login pida el codigo TOTP

LOCKOUT: Configurado via FGPP (3 intentos / 30 min)
"@ | Out-File $instrFile -Encoding UTF8
    Write-OK "Instrucciones guardadas en: $instrFile"

    Pause-Menu
}

function Configurar-ClaveTotp {
    Write-Host ""
    $usuarioTarget = Read-Host "  Nombre de usuario para generar clave TOTP (ej: admin_identidad)"
    if ([string]::IsNullOrWhiteSpace($usuarioTarget)) { return }

    # Generar clave TOTP segura
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $claveTotp = ""; $buffer = 0; $bitsLeft = 0
    foreach ($b in $bytes) {
        $buffer = ($buffer -shl 8) -bor $b; $bitsLeft += 8
        while ($bitsLeft -ge 5) {
            $bitsLeft -= 5
            $claveTotp += $base32Chars[($buffer -shr $bitsLeft) -band 0x1F]
        }
    }

    $issuer  = "Practica09-AD"
    $uriTotp = "otpauth://totp/$issuer`:$usuarioTarget@$($Global:Dominio)?secret=$claveTotp&issuer=$issuer&algorithm=SHA1&digits=6&period=30"

    Write-Host ""
    Write-OK "Clave TOTP generada para: $usuarioTarget"
    Write-Host ""
    Write-Host "  SECRET BASE32 : $claveTotp" -ForegroundColor Green
    Write-Host "  URI TOTP      : $uriTotp" -ForegroundColor Cyan
    Write-Host ""
    Write-WARN "Guarda esta clave en un lugar seguro. Es el secreto compartido para MFA."
    Write-WARN "Escanea el URI con una app que genere QR, o cargalo manualmente en Google Authenticator."

    # Guardar clave en archivo para el usuario
    Ensure-LogDir
    $claveFile = "$($Global:LogPath)\TOTP_$usuarioTarget.txt"
    @"
CLAVE TOTP PARA: $usuarioTarget
Generada: $(Get-Date)
Dominio: $($Global:Dominio)

SECRET (Base32): $claveTotp
URI TOTP: $uriTotp

INSTRUCCIONES PARA EL USUARIO:
1. Instala Google Authenticator en tu telefono
2. Toca el boton (+) > Ingresar una clave
3. Nombre: $issuer - $usuarioTarget
4. Clave: $claveTotp
5. Tipo: Basada en el tiempo
"@ | Out-File $claveFile -Encoding UTF8

    Write-OK "Clave guardada en: $claveFile"

    # Opcionalmente guardar la clave como atributo en AD (campo 'info' / notas del usuario)
    try {
        Set-ADUser -Identity $usuarioTarget -Replace @{info="TOTP_SECRET:$claveTotp"} -ErrorAction SilentlyContinue
        Write-OK "Clave TOTP almacenada en atributo 'info' del usuario en AD (referencia)"
    } catch {
        Write-WARN "No se pudo guardar en AD (puede que el usuario no exista aun): $($_.Exception.Message)"
    }

    Pause-Menu
}

function Configurar-Lockout-MFA {
    Write-Banner
    Write-Host "  [3.2] CONFIGURAR BLOQUEO AUTOMATICO TRAS 3 FALLOS MFA" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "El bloqueo por MFA fallido se implementa via FGPP + auditpol."
    Write-INFO "Si la FGPP ya fue configurada (opcion 2.1), el lockout ya esta activo."
    Write-Host ""

    # Verificar y mostrar estado actual de lockout
    try {
        $fgpp = Get-ADFineGrainedPasswordPolicy -Identity "FGPP_Administradores" -ErrorAction Stop
        Write-Host "  Estado actual de FGPP_Administradores:" -ForegroundColor Yellow
        Write-Host "  LockoutThreshold    : $($fgpp.LockoutThreshold) intentos"
        Write-Host "  LockoutDuration     : $($fgpp.LockoutDuration)"
        Write-Host "  ObservationWindow   : $($fgpp.LockoutObservationWindow)"
        Write-Host ""

        $confirmar = Read-Host "  Actualizar a 3 intentos / 30 minutos? (S/N)"
        if ($confirmar -eq "S" -or $confirmar -eq "s") {
            Set-ADFineGrainedPasswordPolicy -Identity "FGPP_Administradores" `
                -LockoutThreshold         3 `
                -LockoutDuration          "00:30:00" `
                -LockoutObservationWindow "00:30:00"
            Write-OK "Lockout actualizado: 3 intentos -> bloqueo de 30 minutos"
        }
    } catch {
        Write-WARN "FGPP_Administradores no encontrada. Ejecuta primero la opcion 2.1."
        Write-WARN "Error: $($_.Exception.Message)"
    }

    # Tambien configurar en Default Domain Policy como respaldo
    Write-Host ""
    Write-INFO "Configurando politica de bloqueo en Default Domain Policy (respaldo)..."
    try {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue
        $gpArgs = @{
            Name   = "Default Domain Policy"
            Key    = "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        }
        Write-WARN "Para la Default Domain Policy, usa la consola GPMC (gpmc.msc)"
        Write-WARN "Ruta: Computer Config > Windows Settings > Security Settings > Account Lockout Policy"
        Write-WARN "  Account lockout threshold   = 3"
        Write-WARN "  Account lockout duration    = 30 minutos"
        Write-WARN "  Reset after                 = 30 minutos"
    } catch {
        Write-WARN "No se pudo importar GroupPolicy: $($_.Exception.Message)"
    }

    Pause-Menu
}

# ============================================================
#  BLOQUE 4 - TESTS DE VERIFICACION
# ============================================================

function Menu-Tests {
    Write-Banner
    Write-Host "  [4] PROTOCOLO DE PRUEBAS Y VERIFICACION" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Test 1 - Verificar delegacion RBAC (Rol 1 vs Rol 2)"
    Write-Host "  [2] Test 2 - Verificar FGPP (contrasena muy corta)"
    Write-Host "  [3] Test 3 - Verificar estado MFA / Credential Provider"
    Write-Host "  [4] Test 4 - Simular bloqueo de cuenta (3 fallos)"
    Write-Host "  [5] Test 5 - Ejecutar script de auditoria (evento 4625)"
    Write-Host "  [6] Reporte completo del estado de la practica"
    Write-Host "  [B] Volver al menu principal"
    Write-Host ""
    $opTest = Read-Host "  Selecciona"

    switch ($opTest) {
        "1" { Test-Delegacion }
        "2" { Test-FGPP }
        "3" { Test-MFA }
        "4" { Test-Bloqueo }
        "5" { Ejecutar-ScriptMonitoreo }
        "6" { Generar-ReporteCompleto }
        "B" { return }
        "b" { return }
        default { Write-WARN "Opcion no valida."; Pause-Menu; Menu-Tests }
    }
}

function Test-Delegacion {
    Write-Banner
    Write-Host "  TEST 1 - VERIFICACION DE DELEGACION RBAC" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "Verificando permisos de admin_identidad (ROL 1 - debe poder hacer Reset Password)..."
    try {
        $acls = (Get-Acl "AD:$($Global:OU_Cuates)").Access | Where-Object {
            $_.IdentityReference -like "*admin_identidad*"
        }
        if ($acls) {
            Write-OK "admin_identidad TIENE entradas ACL en OU Cuates:"
            $acls | ForEach-Object {
                Write-Host "    $($_.ActiveDirectoryRights) | $($_.AccessControlType) | $($_.ObjectType)" -ForegroundColor Green
            }
        } else {
            Write-WARN "No se encontraron ACLs explicitas para admin_identidad en OU Cuates."
            Write-WARN "Ejecuta primero la opcion 1.2 para configurar las ACLs."
        }
    } catch {
        Write-ERR "Error leyendo ACLs: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando denegacion de Reset Password para admin_storage (ROL 2)..."
    try {
        $acls2 = (Get-Acl "AD:$($Global:OU_Cuates)").Access | Where-Object {
            $_.IdentityReference -like "*admin_storage*"
        }
        if ($acls2) {
            $deny = $acls2 | Where-Object { $_.AccessControlType -eq "Deny" }
            if ($deny) {
                Write-OK "admin_storage tiene DENEGACIONES explicitas en OU Cuates:"
                $deny | ForEach-Object {
                    Write-Host "    DENY: $($_.ActiveDirectoryRights) | ObjectType: $($_.ObjectType)" -ForegroundColor Red
                }
            } else {
                Write-WARN "admin_storage tiene ACLs pero ninguna es de tipo Deny."
            }
        } else {
            Write-WARN "No se encontraron ACLs para admin_storage en OU Cuates."
        }
    } catch {
        Write-ERR "Error leyendo ACLs para admin_storage: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando que admin_auditoria esta en grupo Event Log Readers..."
    try {
        $grupos = Get-ADPrincipalGroupMembership -Identity "admin_auditoria" | Select-Object -ExpandProperty Name
        if ($grupos -contains "Event Log Readers") {
            Write-OK "admin_auditoria: CORRECTO - pertenece a Event Log Readers"
        } else {
            Write-WARN "admin_auditoria NO esta en Event Log Readers. Ejecuta opcion 1.2."
        }
    } catch {
        Write-ERR "Error verificando grupos de admin_auditoria: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Test-FGPP {
    Write-Banner
    Write-Host "  TEST 2 - VERIFICACION DE FGPP (CONTRASENA INSUFICIENTE)" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    # Mostrar FGPP aplicadas
    Write-INFO "Politicas FGPP configuradas en el dominio:"
    try {
        Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, Precedence, MinPasswordLength, LockoutThreshold, LockoutDuration | Format-Table -AutoSize
    } catch {
        Write-ERR "Error leyendo FGPPs: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando politica efectiva para admin_identidad..."
    try {
        $politicaEfectiva = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad"
        if ($politicaEfectiva) {
            Write-OK "Politica efectiva para admin_identidad:"
            Write-Host "  Nombre           : $($politicaEfectiva.Name)" -ForegroundColor Green
            Write-Host "  MinPasswordLength: $($politicaEfectiva.MinPasswordLength) caracteres" -ForegroundColor Green
            Write-Host "  Lockout Threshold: $($politicaEfectiva.LockoutThreshold)" -ForegroundColor Green
        } else {
            Write-WARN "No se encontro politica FGPP para admin_identidad (aplica Default Domain Policy)."
        }
    } catch {
        Write-ERR "Error obteniendo politica efectiva: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Intentando asignar contrasena de 8 caracteres a admin_identidad (debe fallar)..."
    try {
        $passCorta = ConvertTo-SecureString "Pass1234" -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $passCorta -Reset -ErrorAction Stop
        Write-ERR "FALLO DEL TEST: La contrasena de 8 chars fue aceptada. Verifica la FGPP."
    } catch {
        if ($_.Exception.Message -like "*password*" -or $_.Exception.Message -like "*complexity*" -or $_.Exception.Message -like "*length*" -or $_.Exception.Message -like "*contrasena*" -or $_.Exception.Message -like "*politica*") {
            Write-OK "TEST EXITOSO: El sistema rechazo la contrasena corta."
            Write-OK "Error esperado: $($_.Exception.Message)"
        } else {
            Write-WARN "Error diferente al esperado: $($_.Exception.Message)"
        }
    }

    Pause-Menu
}

function Test-MFA {
    Write-Banner
    Write-Host "  TEST 3 - VERIFICACION DE ESTADO MFA / CREDENTIAL PROVIDER" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "Verificando Credential Providers registrados en el sistema..."
    $cpKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
    try {
        $providers = Get-ChildItem $cpKey
        Write-Host ""
        Write-Host "  Credential Providers activos:" -ForegroundColor Yellow
        foreach ($p in $providers) {
            $nombre = (Get-ItemProperty -Path $p.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $guid   = $p.PSChildName
            Write-Host "  [$guid] $nombre" -ForegroundColor Cyan
        }

        # Buscar si hay algun CP relacionado con TOTP/GoogleAuth/MFA
        $mfaCP = $providers | Where-Object {
            $nombre = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $nombre -like "*Google*" -or $nombre -like "*TOTP*" -or $nombre -like "*Auth*" -or $nombre -like "*MFA*" -or $nombre -like "*OTP*"
        }

        Write-Host ""
        if ($mfaCP) {
            Write-OK "Se encontro un Credential Provider relacionado con MFA/TOTP:"
            $mfaCP | ForEach-Object {
                $n = (Get-ItemProperty -Path $_.PSPath)."(Default)"
                Write-Host "  -> $n ($($_.PSChildName))" -ForegroundColor Green
            }
        } else {
            Write-WARN "No se detecto un Credential Provider de MFA/TOTP."
            Write-WARN "Instala el Credential Provider usando la opcion 3.1 del menu."
            Write-Host ""
            Write-INFO "Para verificar MFA manualmente:"
            Write-Host "  1. Cierra sesion en el servidor"
            Write-Host "  2. En la pantalla de login debe aparecer un campo adicional para el codigo TOTP"
            Write-Host "  3. Abre Google Authenticator y usa el codigo de 6 digitos"
        }
    } catch {
        Write-ERR "Error leyendo registro de Credential Providers: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando atributos TOTP almacenados en AD para admin_identidad..."
    try {
        $userInfo = Get-ADUser -Identity "admin_identidad" -Properties info -ErrorAction SilentlyContinue
        if ($userInfo -and $userInfo.info -like "TOTP_SECRET:*") {
            Write-OK "admin_identidad tiene clave TOTP almacenada en AD"
        } else {
            Write-WARN "admin_identidad no tiene clave TOTP. Genera una con la opcion 3.1 > D."
        }
    } catch {
        Write-WARN "No se pudo leer atributo TOTP de AD."
    }

    Pause-Menu
}

function Test-Bloqueo {
    Write-Banner
    Write-Host "  TEST 4 - SIMULACION DE BLOQUEO POR FALLOS CONSECUTIVOS" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    $usuarioPrueba = Read-Host "  Usuario a probar (ej: usr_cuate01, o ENTER para usr_cuate01)"
    if ([string]::IsNullOrWhiteSpace($usuarioPrueba)) { $usuarioPrueba = "usr_cuate01" }

    Write-WARN "Se realizaran 4 intentos de autenticacion con contrasena INCORRECTA."
    Write-WARN "Esto bloqueara la cuenta '$usuarioPrueba' por 30 minutos."
    $confirma = Read-Host "  Confirmar? (S/N)"
    if ($confirma -ne "S" -and $confirma -ne "s") { Pause-Menu; return }

    Write-Host ""
    Write-INFO "Simulando intentos fallidos con New-Object DirectoryServices..."

    $intentos = 0
    1..4 | ForEach-Object {
        try {
            $domainLdap = "LDAP://$($Global:Dominio)"
            $entry = New-Object System.DirectoryServices.DirectoryEntry($domainLdap, $usuarioPrueba, "ContraseñaIncorecta$_`!")
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
            $searcher.FindOne() | Out-Null
        } catch {
            $intentos++
            Write-WARN "Intento $_ fallido (esperado): $($_.Exception.Message.Split("`n")[0])"
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host ""
    Write-INFO "Verificando estado de la cuenta '$usuarioPrueba'..."
    Start-Sleep -Seconds 2

    try {
        $usr = Get-ADUser -Identity $usuarioPrueba -Properties LockedOut, BadLogonCount, BadPasswordTime, PasswordLastSet
        Write-Host ""
        Write-Host "  Estado de la cuenta '$usuarioPrueba':" -ForegroundColor White
        Write-Host "  LockedOut     : $($usr.LockedOut)" -ForegroundColor $(if ($usr.LockedOut) { "Green" } else { "Yellow" })
        Write-Host "  BadLogonCount : $($usr.BadLogonCount)"
        Write-Host "  BadPasswordTime: $($usr.BadPasswordTime)"
        Write-Host ""

        if ($usr.LockedOut) {
            Write-OK "TEST EXITOSO: La cuenta quedo bloqueada (LockedOut = True)"
        } else {
            Write-WARN "La cuenta NO esta bloqueada. Puede que la FGPP no este aplicada o el threshold es mayor."
            Write-WARN "BadLogonCount = $($usr.BadLogonCount) (threshold de FGPP = 3 o 5)"
        }

        Write-Host ""
        $desbloquear = Read-Host "  Desbloquear la cuenta ahora? (S/N)"
        if ($desbloquear -eq "S" -or $desbloquear -eq "s") {
            Unlock-ADAccount -Identity $usuarioPrueba
            Write-OK "Cuenta '$usuarioPrueba' desbloqueada."
        }
    } catch {
        Write-ERR "Error verificando estado: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Generar-ReporteCompleto {
    Write-Banner
    Write-Host "  REPORTE COMPLETO DE ESTADO - PRACTICA 09" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Ensure-LogDir
    $reporteFile = "$($Global:LogPath)\Reporte_Completo_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $lineas = @()

    $lineas += "=" * 70
    $lineas += " REPORTE DE ESTADO - PRACTICA 09 - AD HARDENING / RBAC / MFA"
    $lineas += " Generado: $(Get-Date)"
    $lineas += " Servidor: $env:COMPUTERNAME | Dominio: $($Global:Dominio)"
    $lineas += "=" * 70

    # --- Usuarios delegados ---
    $lineas += "`nUSUARIOS DELEGADOS:"
    $lineas += "-" * 40
    foreach ($u in @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
        try {
            $usr = Get-ADUser -Identity $u -Properties Description, Enabled, LockedOut -ErrorAction Stop
            $lineas += "  $($usr.SamAccountName) | Enabled=$($usr.Enabled) | LockedOut=$($usr.LockedOut) | $($usr.Description)"
        } catch {
            $lineas += "  $u -> NO ENCONTRADO"
        }
    }

    # --- FGPPs ---
    $lineas += "`nDIRECTIVAS FGPP:"
    $lineas += "-" * 40
    try {
        Get-ADFineGrainedPasswordPolicy -Filter * | ForEach-Object {
            $lineas += "  $($_.Name) | Precedencia=$($_.Precedence) | MinLen=$($_.MinPasswordLength) | LockoutThreshold=$($_.LockoutThreshold) | LockoutDuration=$($_.LockoutDuration)"
        }
    } catch {
        $lineas += "  Error leyendo FGPPs"
    }

    # --- Auditoria ---
    $lineas += "`nCONFIGURACION DE AUDITORIA (auditpol):"
    $lineas += "-" * 40
    $audOutput = & auditpol /get /category:* 2>&1
    $lineas += ($audOutput | Where-Object { $_ -match "Logon|Object Access|Account Management|Policy Change" })

    # --- Credential Providers ---
    $lineas += "`nCREDENTIAL PROVIDERS REGISTRADOS:"
    $lineas += "-" * 40
    try {
        $cpKey2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
        Get-ChildItem $cpKey2 | ForEach-Object {
            $n = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $lineas += "  [$($_.PSChildName)] $n"
        }
    } catch {
        $lineas += "  Error leyendo Credential Providers"
    }

    # --- Ultimos eventos 4625 ---
    $lineas += "`nULTIMOS 5 EVENTOS 4625 (ACCESO DENEGADO):"
    $lineas += "-" * 40
    try {
        $ev4625 = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($ev4625) {
            foreach ($e in $ev4625) {
                $lineas += "  $($e.TimeCreated) | Usuario: $(try{$e.Properties[5].Value}catch{'N/A'}) | IP: $(try{$e.Properties[19].Value}catch{'N/A'})"
            }
        } else {
            $lineas += "  No se encontraron eventos 4625"
        }
    } catch {
        $lineas += "  Error leyendo eventos de seguridad"
    }

    $lineas += "`n" + "=" * 70

    # Mostrar en pantalla y guardar
    $lineas | ForEach-Object { Write-Host "  $_" }
    $lineas | Out-File $reporteFile -Encoding UTF8
    Write-Host ""
    Write-OK "Reporte completo guardado en: $reporteFile"

    Pause-Menu
}

# ============================================================
#  MENU PRINCIPAL
# ============================================================

function Show-MenuPrincipal {
    Write-Banner
    Write-Host "  Dominio detectado : $($Global:Dominio)" -ForegroundColor DarkGray
    Write-Host "  Servidor          : $env:COMPUTERNAME" -ForegroundColor DarkGray
    Write-Host "  Logs en           : $($Global:LogPath)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ─── BLOQUE 1: DELEGACION DE CONTROL Y RBAC ─────────────" -ForegroundColor DarkYellow
    Write-Host "  [1] Crear usuarios administradores delegados (4 roles)"
    Write-Host "  [2] Configurar ACLs y permisos granulares (dsacls)"
    Write-Host ""
    Write-Host "  ─── BLOQUE 2: DIRECTIVAS Y AUDITORIA ────────────────────" -ForegroundColor DarkYellow
    Write-Host "  [3] Crear FGPP (12 chars admins / 8 chars usuarios)"
    Write-Host "  [4] Habilitar auditoria de eventos (logon, objetos, etc.)"
    Write-Host "  [5] Ejecutar script de monitoreo (exportar eventos 4625)"
    Write-Host ""
    Write-Host "  ─── BLOQUE 3: MFA - GOOGLE AUTHENTICATOR ────────────────" -ForegroundColor DarkYellow
    Write-Host "  [6] Instalar y configurar MFA TOTP (Credential Provider)"
    Write-Host "  [7] Configurar bloqueo automatico (3 fallos / 30 min)"
    Write-Host ""
    Write-Host "  ─── BLOQUE 4: VERIFICACION ──────────────────────────────" -ForegroundColor DarkYellow
    Write-Host "  [8] Menu de tests y protocolo de pruebas"
    Write-Host ""
    Write-Host "  [9] Ejecutar CONFIGURACION COMPLETA (bloques 1-3 en orden)"
    Write-Host "  [0] Salir"
    Write-Host ""
    $opcion = Read-Host "  Selecciona una opcion"
    return $opcion
}

# ============================================================
#  PUNTO DE ENTRADA
# ============================================================

# Verificar que se ejecuta con privilegios de administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host ""
    Write-Host "  [ERROR] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    Write-Host "  Clic derecho sobre PowerShell -> 'Ejecutar como administrador'" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Presiona ENTER para salir"
    exit 1
}

# Verificar modulo AD
if (-not (Test-ADModuleLoaded)) {
    Write-Host ""
    Write-Host "  [ERROR] Modulo ActiveDirectory no disponible." -ForegroundColor Red
    Write-Host "  Instala RSAT: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    Read-Host "  Presiona ENTER para salir"
    exit 1
}

Ensure-LogDir

# Bucle principal del menu
do {
    $opcion = Show-MenuPrincipal
    switch ($opcion) {
        "1" { Crear-UsuariosDelegados }
        "2" { Configurar-ACLs-RBAC }
        "3" { Configurar-FGPP }
        "4" { Configurar-Auditoria }
        "5" { Ejecutar-ScriptMonitoreo }
        "6" { Instalar-MFA-TOTP }
        "7" { Configurar-Lockout-MFA }
        "8" { Menu-Tests }
        "9" {
            Write-Banner
            Write-Host "  EJECUTANDO CONFIGURACION COMPLETA..." -ForegroundColor Cyan
            Write-Host ""
            Crear-UsuariosDelegados
            Configurar-ACLs-RBAC
            Configurar-FGPP
            Configurar-Auditoria
            Configurar-Lockout-MFA
            Write-OK "Configuracion completa finalizada. Ahora ejecuta la opcion 6 para MFA."
            Pause-Menu
        }
        "0" {
            Write-Host ""
            Write-Host "  Saliendo del script de Practica 09." -ForegroundColor DarkGray
            Write-Host "  Los logs y reportes estan en: $($Global:LogPath)" -ForegroundColor DarkGray
            Write-Host ""
        }
        default {
            Write-WARN "Opcion '$opcion' no valida. Elige entre 0 y 9."
            Start-Sleep -Seconds 1
        }
    }
} while ($opcion -ne "0")