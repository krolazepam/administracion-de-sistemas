# ============================================================
#  CONFIGURACION GLOBAL - Ajusta estos valores a tu entorno
# ============================================================
$Global:Dominio     = $env:USERDNSDOMAIN
$Global:DominioNB   = $env:USERDOMAIN
$Global:DCBase      = (Get-ADDomain).DistinguishedName
$Global:OU_Admins   = "OU=AdminsDelegados,$($Global:DCBase)"
$Global:OU_Cuates   = "OU=Cuates,$($Global:DCBase)"
$Global:OU_NoCuates = "OU=NoCuates,$($Global:DCBase)"
$Global:LogPath     = "C:\Practica09\Logs"

# ============================================================
#  FUNCIONES DE UTILIDAD
# ============================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |      PRACTICA 09 - AD HARDENING / RBAC / MFA               |" -ForegroundColor Cyan
    Write-Host "  |      Seguridad Avanzada en Active Directory                 |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK   { param($msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-ERR  { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-INFO { param($msg) Write-Host "  [..]  $msg" -ForegroundColor Cyan }
function Write-WARN { param($msg) Write-Host "  [!]   $msg" -ForegroundColor Yellow }

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
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    Crear-OUsBase

    $usuarios = @(
        @{ Nombre="admin_identidad"; Descripcion="Rol 1 - IAM Operator: Gestion ciclo de vida de usuarios" },
        @{ Nombre="admin_storage";   Descripcion="Rol 2 - Storage Operator: Gestion de cuotas y FSRM" },
        @{ Nombre="admin_politicas"; Descripcion="Rol 3 - GPO Compliance: Gestion de directivas de grupo" },
        @{ Nombre="admin_auditoria"; Descripcion="Rol 4 - Security Auditor: Solo lectura de eventos" }
    )

    Write-WARN "Contrasena inicial para todos los usuarios delegados: Admin@Practica09!"
    Write-WARN "Cambiala antes de usar en produccion."
    Write-Host ""

    $passSegura = ConvertTo-SecureString "Admin@Practica09!" -AsPlainText -Force

    foreach ($u in $usuarios) {
        try {
            $nombre = $u.Nombre
            $existe = Get-ADUser -Filter "SamAccountName -eq '$nombre'" -ErrorAction SilentlyContinue
            if ($existe) {
                Write-WARN "Usuario '$nombre' ya existe. Se omite."
            } else {
                New-ADUser `
                    -Name                 $u.Nombre `
                    -SamAccountName       $u.Nombre `
                    -UserPrincipalName    "$($u.Nombre)@$($Global:Dominio)" `
                    -Description          $u.Descripcion `
                    -Path                 $Global:OU_Admins `
                    -AccountPassword      $passSegura `
                    -Enabled              $true `
                    -PasswordNeverExpires $false `
                    -ChangePasswordAtLogon $false
                Write-OK "Creado: $($u.Nombre)"
            }
        } catch {
            Write-ERR "Error creando $($u.Nombre): $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-INFO "Creando usuarios de prueba en OU Cuates y NoCuates..."
    $usuariosTest = @("usr_cuate01","usr_cuate02","usr_nocuate01")
    foreach ($u in $usuariosTest) {
        try {
            $existe = Get-ADUser -Filter "SamAccountName -eq '$u'" -ErrorAction SilentlyContinue
            if (-not $existe) {
                $ouDestino = if ($u -like "*nocuate*") { $Global:OU_NoCuates } else { $Global:OU_Cuates }
                New-ADUser -Name $u -SamAccountName $u -Path $ouDestino `
                    -AccountPassword (ConvertTo-SecureString "UserPass@2024!" -AsPlainText -Force) `
                    -Enabled $true -ChangePasswordAtLogon $false
                Write-OK "Creado usuario de prueba: $u"
            }
        } catch {
            Write-WARN "No se pudo crear $u : $($_.Exception.Message)"
        }
    }

    Pause-Menu
}

function Configurar-ACLs-RBAC {
    Write-Banner
    Write-Host "  [1.2] CONFIGURAR ACLs Y PERMISOS GRANULARES" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    $ousCubiertos = @($Global:OU_Cuates, $Global:OU_NoCuates)

    # ROL 1: admin_identidad
    Write-Host "  ROL 1 - admin_identidad (IAM Operator)" -ForegroundColor Yellow
    foreach ($ou in $ousCubiertos) {
        try {
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:CCDC;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:CA;Reset Password;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;telephoneNumber;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;physicalDeliveryOfficeName;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;mail;user" /I:S 2>&1 | Out-Null
            & dsacls $ou /G "$($Global:DominioNB)\admin_identidad:RPWP;lockoutTime;user" /I:S 2>&1 | Out-Null
            Write-OK "Permisos IAM Operator aplicados en: $ou"
        } catch {
            Write-ERR "Error ROL 1 en $ou : $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Host "  ROL 2 - admin_storage (Storage Operator - DENY Reset Password)" -ForegroundColor Yellow
    foreach ($ou in $ousCubiertos) {
        try {
            & dsacls $ou /D "$($Global:DominioNB)\admin_storage:CA;Reset Password;user" /I:S 2>&1 | Out-Null
            Write-OK "DENY Reset Password aplicado para admin_storage en: $ou"
        } catch {
            Write-ERR "Error ROL 2 en $ou : $($_.Exception.Message)"
        }
    }
    try {
        Add-ADGroupMember -Identity "Server Operators" -Members "admin_storage" -ErrorAction SilentlyContinue
        Write-OK "admin_storage agregado a Server Operators (acceso FSRM)"
    } catch {
        Write-WARN "No se pudo agregar admin_storage a Server Operators"
    }

    Write-Host ""
    Write-Host "  ROL 3 - admin_politicas (GPO Compliance)" -ForegroundColor Yellow
    try {
        & dsacls $Global:DCBase /G "$($Global:DominioNB)\admin_politicas:GR" 2>&1 | Out-Null
        Write-OK "Lectura global aplicada para admin_politicas"
        & dsacls $Global:OU_Cuates   /G "$($Global:DominioNB)\admin_politicas:RPWP;gPLink" 2>&1 | Out-Null
        & dsacls $Global:OU_NoCuates /G "$($Global:DominioNB)\admin_politicas:RPWP;gPLink" 2>&1 | Out-Null
        & dsacls $Global:OU_Cuates   /D "$($Global:DominioNB)\admin_politicas:WP;;user" 2>&1 | Out-Null
        Write-OK "admin_politicas: lectura global, escritura solo en gPLink"
    } catch {
        Write-ERR "Error ROL 3: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "  ROL 4 - admin_auditoria (Security Auditor - Solo Lectura)" -ForegroundColor Yellow
    try {
        & dsacls $Global:DCBase /G "$($Global:DominioNB)\admin_auditoria:GR" /I:T 2>&1 | Out-Null
        Write-OK "Solo lectura aplicado para admin_auditoria en el dominio"
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction SilentlyContinue
        Write-OK "admin_auditoria agregado al grupo Event Log Readers"
    } catch {
        Write-ERR "Error ROL 4: $($_.Exception.Message)"
    }

    Pause-Menu
}

# ============================================================
#  BLOQUE 2 - FGPP Y AUDITORIA
# ============================================================

function Configurar-FGPP {
    Write-Banner
    Write-Host "  [2.1] DIRECTIVAS DE CONTRASENA AJUSTADA (FGPP)" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-ADModuleLoaded)) { Pause-Menu; return }

    $nivelFuncional = (Get-ADDomain).DomainMode
    Write-INFO "Nivel funcional del dominio: $nivelFuncional"

    # FGPP para administradores: minimo 12 caracteres
    Write-Host ""
    Write-Host "  Creando politica para ADMINISTRADORES - minimo 12 caracteres..." -ForegroundColor Yellow
    try {
        $existeFGPP = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Administradores'" -ErrorAction SilentlyContinue
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
        $msg = "FGPP_Administradores configurada: min 12 chars, lockout 3 intentos / 30 min"
        Write-OK $msg
    } catch {
        Write-ERR "Error creando FGPP para admins: $($_.Exception.Message)"
    }

    # FGPP para usuarios estandar: minimo 8 caracteres
    Write-Host ""
    Write-Host "  Creando politica para USUARIOS ESTANDAR - minimo 8 caracteres..." -ForegroundColor Yellow
    try {
        $existeFGPP2 = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Usuarios'" -ErrorAction SilentlyContinue
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
        $msg2 = "FGPP_Usuarios configurada: min 8 chars, lockout 5 intentos / 30 min"
        Write-OK $msg2
    } catch {
        Write-ERR "Error creando FGPP para usuarios: $($_.Exception.Message)"
    }

    # Aplicar FGPP a usuarios delegados
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

    # Grupo para usuarios estandar
    Write-Host ""
    Write-INFO "Creando grupo GG_UsuariosEstandar para FGPP_Usuarios..."
    try {
        $grpExiste = Get-ADGroup -Filter "Name -eq 'GG_UsuariosEstandar'" -ErrorAction SilentlyContinue
        if (-not $grpExiste) {
            New-ADGroup -Name "GG_UsuariosEstandar" -GroupScope Global -Path $Global:DCBase
            Write-OK "Grupo GG_UsuariosEstandar creado"
        }
        Add-ADGroupMember -Identity "GG_UsuariosEstandar" -Members "usr_cuate01","usr_cuate02","usr_nocuate01" -ErrorAction SilentlyContinue
        Add-ADFineGrainedPasswordPolicySubject -Identity "FGPP_Usuarios" -Subjects "GG_UsuariosEstandar" -ErrorAction SilentlyContinue
        Write-OK "FGPP_Usuarios aplicada al grupo GG_UsuariosEstandar"
    } catch {
        Write-WARN "Advertencia con grupo usuarios estandar: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Configurar-Auditoria {
    Write-Banner
    Write-Host "  [2.2] HARDENING DE AUDITORIA DE EVENTOS" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "Habilitando auditoria de Logon..."
    try {
        & auditpol /set /subcategory:"Logon" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"Logoff" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria Logon/Logoff habilitada"
    } catch {
        Write-ERR "Error en auditoria Logon: $($_.Exception.Message)"
    }

    Write-INFO "Habilitando auditoria de acceso a objetos..."
    try {
        & auditpol /set /subcategory:"Object Access" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"File System" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria Object Access y File System habilitada"
    } catch {
        Write-ERR "Error en auditoria de objetos: $($_.Exception.Message)"
    }

    Write-INFO "Habilitando auditoria de gestion de cuentas..."
    try {
        & auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable 2>&1 | Out-Null
        & auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria User/Group Management habilitada"
    } catch {
        Write-ERR "Error en auditoria de cuentas: $($_.Exception.Message)"
    }

    Write-INFO "Habilitando auditoria de cambios de politica..."
    try {
        & auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria Policy Change habilitada"
    } catch {
        Write-ERR "Error en auditoria de politica: $($_.Exception.Message)"
    }

    Write-INFO "Habilitando auditoria de uso de privilegios..."
    try {
        & auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "Auditoria Sensitive Privilege Use habilitada"
    } catch {
        Write-ERR "Error en auditoria de privilegios: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Estado actual de auditoria relevante:"
    & auditpol /get /category:* 2>&1 | Where-Object { $_ -match "Logon|Object|Account|Policy" }

    Pause-Menu
}

function Ejecutar-ScriptMonitoreo {
    Write-Banner
    Write-Host "  [2.3] SCRIPT DE MONITOREO - EVENTOS 4625 (ACCESO DENEGADO)" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Ensure-LogDir

    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $archivoCSV = "$($Global:LogPath)\AccesosDenegados_$timestamp.csv"
    $archivoTXT = "$($Global:LogPath)\AccesosDenegados_$timestamp.txt"

    Write-INFO "Extrayendo ultimos 10 eventos ID 4625 del log de Seguridad..."

    try {
        $eventos = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id      = 4625
        } -MaxEvents 10 -ErrorAction SilentlyContinue

        if (-not $eventos) {
            Write-WARN "No se encontraron eventos 4625. Generando intento fallido de prueba..."
            $credFalsa = New-Object System.Management.Automation.PSCredential(
                "usuarioInvalido99",
                (ConvertTo-SecureString "claveInvalida99!" -AsPlainText -Force)
            )
            try {
                Start-Process -FilePath "cmd.exe" -Credential $credFalsa -WindowStyle Hidden -ErrorAction SilentlyContinue
            } catch {}
            Start-Sleep -Seconds 2
            $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        }

        if ($eventos) {
            $resultado = foreach ($e in $eventos) {
                $usuarioEvt = try { $e.Properties[5].Value  } catch { "N/A" }
                $dominioEvt = try { $e.Properties[6].Value  } catch { "N/A" }
                $procesoEvt = try { $e.Properties[11].Value } catch { "N/A" }
                $tipoFallo  = try { $e.Properties[8].Value  } catch { "N/A" }
                $ipOrigen   = try { $e.Properties[19].Value } catch { "N/A" }
                $puertoOrig = try { $e.Properties[20].Value } catch { "N/A" }

                [PSCustomObject]@{
                    Fecha_Hora    = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    EventoID      = $e.Id
                    TipoFallo     = $tipoFallo
                    Usuario       = $usuarioEvt
                    Dominio       = $dominioEvt
                    Proceso       = $procesoEvt
                    IP_Origen     = $ipOrigen
                    Puerto_Origen = $puertoOrig
                    Descripcion   = "Intento fallido de inicio de sesion"
                }
            }

            $resultado | Export-Csv -Path $archivoCSV -NoTypeInformation -Encoding UTF8
            Write-OK "Exportado CSV: $archivoCSV"

            $lineasTXT  = @()
            $separador  = "=" * 70
            $separador2 = "-" * 60
            $lineasTXT += $separador
            $lineasTXT += " REPORTE DE ACCESOS DENEGADOS - EVENTO ID 4625"
            $lineasTXT += " Generado   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lineasTXT += " Servidor   : $env:COMPUTERNAME"
            $lineasTXT += " Dominio    : $($Global:Dominio)"
            $lineasTXT += $separador
            $lineasTXT += ""

            $i = 1
            foreach ($r in $resultado) {
                $lineasTXT += "  EVENTO #$i"
                $lineasTXT += "  Fecha/Hora  : $($r.Fecha_Hora)"
                $lineasTXT += "  Usuario     : $($r.Usuario) @ $($r.Dominio)"
                $lineasTXT += "  IP Origen   : $($r.IP_Origen) : $($r.Puerto_Origen)"
                $lineasTXT += "  Proceso     : $($r.Proceso)"
                $lineasTXT += "  Tipo Fallo  : $($r.TipoFallo)"
                $lineasTXT += "  $separador2"
                $i++
            }

            $totalMsg = "  Total eventos encontrados: $($resultado.Count)"
            $lineasTXT += ""
            $lineasTXT += $totalMsg
            $lineasTXT | Out-File -FilePath $archivoTXT -Encoding UTF8
            Write-OK "Exportado TXT: $archivoTXT"

            Write-Host ""
            Write-Host "  RESUMEN:" -ForegroundColor White
            $resultado | Format-Table Fecha_Hora, Usuario, Dominio, IP_Origen -AutoSize

        } else {
            Write-WARN "No se encontraron eventos 4625."
            Write-WARN "Asegurate de que la auditoria de Logon este habilitada (opcion 4)."
            $noEvt = "Sin eventos 4625. Fecha: $(Get-Date)"
            $noEvt | Out-File $archivoTXT -Encoding UTF8
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
    Write-Host "  [3.1] CONFIGURACION MFA - GOOGLE AUTHENTICATOR (TOTP)" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Opciones disponibles:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [A] Descargar WinAuth (generador TOTP de escritorio)" -ForegroundColor Cyan
    Write-Host "  [B] Instrucciones para instalar Credential Provider" -ForegroundColor Cyan
    Write-Host "  [C] Mostrar instrucciones completas de configuracion MFA" -ForegroundColor Cyan
    Write-Host "  [D] Generar clave TOTP para un usuario" -ForegroundColor Cyan
    Write-Host "  [E] Volver al menu principal" -ForegroundColor DarkGray
    Write-Host ""
    $opMFA = Read-Host "  Selecciona una opcion"

    switch ($opMFA.ToUpper()) {
        "A" { Instalar-MFA-WinAuth }
        "B" { Instalar-MFA-CredProvider }
        "C" { Mostrar-InstruccionesMFA }
        "D" { Configurar-ClaveTotp }
        "E" { return }
        default { Write-WARN "Opcion no valida."; Pause-Menu }
    }
}

function Instalar-MFA-WinAuth {
    Write-Host ""
    Write-INFO "Intentando descargar WinAuth desde GitHub..."
    $urlWinAuth = "https://github.com/winauth/winauth/releases/latest/download/WinAuth.exe"
    $destino    = "C:\Practica09\WinAuth.exe"

    try {
        if (-not (Test-Path "C:\Practica09")) {
            New-Item -ItemType Directory -Path "C:\Practica09" -Force | Out-Null
        }
        Invoke-WebRequest -Uri $urlWinAuth -OutFile $destino -UseBasicParsing -TimeoutSec 60
        Write-OK "WinAuth descargado en: $destino"
        Write-WARN "WinAuth genera tokens TOTP pero NO es un Credential Provider de Windows."
        Write-WARN "Para MFA en el login de Windows usa la opcion B."
    } catch {
        Write-ERR "No se pudo descargar WinAuth: $($_.Exception.Message)"
        Write-INFO "Descarga manual: https://winauth.github.io/winauth/"
    }
    Pause-Menu
}

function Instalar-MFA-CredProvider {
    Write-Host ""
    Write-WARN "El Credential Provider de Google Authenticator requiere compilacion"
    Write-WARN "desde codigo fuente o un instalador de terceros."
    Write-Host ""
    Write-INFO "Repositorios recomendados para laboratorio:"
    Write-Host "  -> github.com/StratumSecurity/GoogleAuthenticatorCredentialProvider" -ForegroundColor Cyan
    Write-Host "  -> github.com/nicowillis/google-authenticator-windows" -ForegroundColor Cyan
    Write-Host ""
    Write-INFO "Pasos de instalacion del Credential Provider compilado:"
    Write-Host ""
    Write-Host "  1. Copia GoogleAuthCP.dll a C:\Windows\System32\" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Registra la clave de registro:" -ForegroundColor White
    $regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{GUID}"
    Write-Host "     reg add `"$regPath`"" -ForegroundColor DarkGray
    Write-Host "     reg add `"$regPath`" /v `"(Default)`" /d `"GoogleAuthCP`"" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3. Reinicia el servidor." -ForegroundColor White
    Write-Host ""

    $dllPath = Read-Host "  Si ya tienes el DLL en System32, escribe su nombre (o ENTER para omitir)"
    if ($dllPath -ne "") {
        try {
            $fullDll = "C:\Windows\System32\$dllPath"
            if (Test-Path $fullDll) {
                & regsvr32 /s $fullDll
                Write-OK "DLL registrado: $fullDll"
                Write-WARN "Reinicia el servidor para activar el Credential Provider en el login."
            } else {
                Write-ERR "Archivo no encontrado: $fullDll"
            }
        } catch {
            Write-ERR "Error al registrar DLL: $($_.Exception.Message)"
        }
    }
    Pause-Menu
}

function Mostrar-InstruccionesMFA {
    Write-Host ""
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |       INSTRUCCIONES DE CONFIGURACION MFA TOTP              |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ARQUITECTURA DEL FLUJO:" -ForegroundColor Yellow
    Write-Host "  1. Usuario ingresa usuario + contrasena en pantalla de login"
    Write-Host "  2. Credential Provider intercepta ANTES de llegar a LSASS"
    Write-Host "  3. LSASS valida credenciales en Active Directory"
    Write-Host "  4. Si OK, el Credential Provider pide codigo TOTP de 6 digitos"
    Write-Host "  5. Se valida el codigo contra el algoritmo TOTP del usuario"
    Write-Host "  6. Si el codigo es correcto: acceso concedido"
    Write-Host "  7. Si falla 3 veces: cuenta bloqueada 30 minutos (via FGPP)"
    Write-Host ""
    Write-Host "  COMPONENTES NECESARIOS:" -ForegroundColor Yellow
    Write-Host "  1. Credential Provider DLL registrado en Windows"
    Write-Host "  2. Clave secreta TOTP por usuario (Base32)"
    Write-Host "  3. App Google Authenticator instalada en el movil"
    Write-Host ""
    Write-Host "  CLAVE DE REGISTRO DE WINDOWS:" -ForegroundColor Yellow
    Write-Host "  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication"
    Write-Host "    \Credential Providers\{GUID-DEL-PROVIDER}"
    Write-Host ""

    # Generar clave de ejemplo
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $b32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $claveEjemplo = ""
    $buf = 0; $bits = 0
    foreach ($b in $bytes) {
        $buf = ($buf -shl 8) -bor $b; $bits += 8
        while ($bits -ge 5) {
            $bits -= 5
            $claveEjemplo += $b32Chars[($buf -shr $bits) -band 0x1F]
        }
    }

    Write-Host "  CLAVE BASE32 DE EJEMPLO:" -ForegroundColor Yellow
    Write-Host "  $claveEjemplo" -ForegroundColor Green
    Write-Host ""
    $uriEjemplo = "otpauth://totp/Practica09:admin_identidad?secret=$claveEjemplo&issuer=Practica09"
    Write-Host "  URI TOTP (para generar QR):" -ForegroundColor Yellow
    Write-Host "  $uriEjemplo" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  BLOQUEO POR MFA FALLIDO:" -ForegroundColor Yellow
    Write-Host "  Gestionado via FGPP: LockoutThreshold=3, LockoutDuration=30 min"
    Write-Host "  Configura esto con la opcion 7 del menu principal."
    Write-Host ""

    Ensure-LogDir
    $instrFile = "$($Global:LogPath)\Instrucciones_MFA.txt"
    $contenido = @(
        "INSTRUCCIONES MFA TOTP - PRACTICA 09",
        "Generado: $(Get-Date)",
        "Dominio: $($Global:Dominio)",
        "",
        "CLAVE TOTP EJEMPLO: $claveEjemplo",
        "URI QR: $uriEjemplo",
        "",
        "PASOS:",
        "1. Instalar Credential Provider DLL en C:\Windows\System32\",
        "2. Registrar el DLL en el registro de Windows",
        "3. Distribuir clave TOTP a cada usuario (escanear QR)",
        "4. Reiniciar el servidor",
        "5. Verificar que login solicite codigo TOTP",
        "",
        "LOCKOUT: Configurado via FGPP - 3 intentos / 30 min"
    )
    $contenido | Out-File $instrFile -Encoding UTF8
    Write-OK "Instrucciones guardadas en: $instrFile"

    Pause-Menu
}

function Configurar-ClaveTotp {
    Write-Host ""
    $usuarioTarget = Read-Host "  Nombre del usuario (ej: admin_identidad)"
    if ([string]::IsNullOrWhiteSpace($usuarioTarget)) { return }

    # Generar clave TOTP segura
    $bytes = New-Object byte[] 20
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $b32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $claveTotp = ""; $buf = 0; $bits = 0
    foreach ($b in $bytes) {
        $buf = ($buf -shl 8) -bor $b; $bits += 8
        while ($bits -ge 5) {
            $bits -= 5
            $claveTotp += $b32Chars[($buf -shr $bits) -band 0x1F]
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
    Write-WARN "Guarda esta clave. Es el secreto compartido para MFA."
    Write-WARN "Cargala manualmente en Google Authenticator o usa el URI para generar un QR."

    Ensure-LogDir
    $claveFile = "$($Global:LogPath)\TOTP_$usuarioTarget.txt"
    $contenidoClave = @(
        "CLAVE TOTP PARA: $usuarioTarget",
        "Generada: $(Get-Date)",
        "Dominio: $($Global:Dominio)",
        "",
        "SECRET Base32: $claveTotp",
        "URI TOTP: $uriTotp",
        "",
        "INSTRUCCIONES PARA EL USUARIO:",
        "1. Instala Google Authenticator en tu telefono",
        "2. Toca el boton (+) > Ingresar una clave de configuracion",
        "3. Nombre: $issuer - $usuarioTarget",
        "4. Clave: $claveTotp",
        "5. Tipo: Basada en el tiempo"
    )
    $contenidoClave | Out-File $claveFile -Encoding UTF8
    Write-OK "Clave guardada en: $claveFile"

    try {
        Set-ADUser -Identity $usuarioTarget -Replace @{info="TOTP_SECRET:$claveTotp"} -ErrorAction SilentlyContinue
        Write-OK "Clave TOTP referenciada en atributo info del usuario en AD"
    } catch {
        Write-WARN "No se pudo guardar en AD: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Configurar-Lockout-MFA {
    Write-Banner
    Write-Host "  [3.2] CONFIGURAR BLOQUEO AUTOMATICO - 3 FALLOS / 30 MIN" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "El bloqueo se gestiona via FGPP. Verificando estado actual..."
    Write-Host ""

    try {
        $fgpp = Get-ADFineGrainedPasswordPolicy -Identity "FGPP_Administradores" -ErrorAction Stop
        Write-Host "  Estado actual de FGPP_Administradores:" -ForegroundColor Yellow
        Write-Host "  LockoutThreshold : $($fgpp.LockoutThreshold) intentos"
        Write-Host "  LockoutDuration  : $($fgpp.LockoutDuration)"
        Write-Host "  ObservWindow     : $($fgpp.LockoutObservationWindow)"
        Write-Host ""

        $confirmar = Read-Host "  Actualizar a 3 intentos y 30 minutos de bloqueo? (S/N)"
        if ($confirmar -eq "S" -or $confirmar -eq "s") {
            Set-ADFineGrainedPasswordPolicy -Identity "FGPP_Administradores" `
                -LockoutThreshold         3 `
                -LockoutDuration          "00:30:00" `
                -LockoutObservationWindow "00:30:00"
            Write-OK "Lockout actualizado: 3 intentos -> bloqueo de 30 minutos"
        }
    } catch {
        Write-WARN "FGPP_Administradores no encontrada. Ejecuta primero la opcion 3."
        Write-WARN "Detalle: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "NOTA: Para la Default Domain Policy usa la consola GPMC (gpmc.msc)"
    Write-INFO "Ruta: Computer Config > Windows Settings > Security Settings > Account Lockout"
    Write-INFO "  Account lockout threshold = 3"
    Write-INFO "  Account lockout duration  = 30 minutos"

    Pause-Menu
}

# ============================================================
#  BLOQUE 4 - TESTS DE VERIFICACION
# ============================================================

function Menu-Tests {
    Write-Banner
    Write-Host "  [4] PROTOCOLO DE PRUEBAS Y VERIFICACION" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Test 1 - Verificar delegacion RBAC (Rol 1 vs Rol 2)"
    Write-Host "  [2] Test 2 - Verificar FGPP (contrasena muy corta debe fallar)"
    Write-Host "  [3] Test 3 - Verificar estado MFA y Credential Provider"
    Write-Host "  [4] Test 4 - Simular bloqueo de cuenta por fallos consecutivos"
    Write-Host "  [5] Test 5 - Generar reporte de auditoria (eventos 4625)"
    Write-Host "  [6] Reporte completo del estado de la practica"
    Write-Host "  [B] Volver al menu principal"
    Write-Host ""
    $opTest = Read-Host "  Selecciona"

    switch ($opTest.ToUpper()) {
        "1" { Test-Delegacion }
        "2" { Test-FGPP }
        "3" { Test-MFA }
        "4" { Test-Bloqueo }
        "5" { Ejecutar-ScriptMonitoreo }
        "6" { Generar-ReporteCompleto }
        "B" { return }
        default { Write-WARN "Opcion no valida."; Pause-Menu; Menu-Tests }
    }
}

function Test-Delegacion {
    Write-Banner
    Write-Host "  TEST 1 - VERIFICACION DE DELEGACION RBAC" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "Verificando ACLs de admin_identidad en OU Cuates..."
    try {
        $acls = (Get-Acl "AD:$($Global:OU_Cuates)").Access | Where-Object {
            $_.IdentityReference -like "*admin_identidad*"
        }
        if ($acls) {
            Write-OK "admin_identidad TIENE entradas ACL en OU Cuates:"
            $acls | ForEach-Object {
                Write-Host "    Derecho: $($_.ActiveDirectoryRights) | Tipo: $($_.AccessControlType)" -ForegroundColor Green
            }
        } else {
            Write-WARN "No hay ACLs explicitas para admin_identidad. Ejecuta la opcion 2."
        }
    } catch {
        Write-ERR "Error leyendo ACLs: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando DENY de Reset Password para admin_storage..."
    try {
        $acls2 = (Get-Acl "AD:$($Global:OU_Cuates)").Access | Where-Object {
            $_.IdentityReference -like "*admin_storage*"
        }
        if ($acls2) {
            $deny = $acls2 | Where-Object { $_.AccessControlType -eq "Deny" }
            if ($deny) {
                Write-OK "admin_storage tiene DENY en OU Cuates:"
                $deny | ForEach-Object {
                    Write-Host "    DENY: $($_.ActiveDirectoryRights)" -ForegroundColor Red
                }
            } else {
                Write-WARN "admin_storage tiene ACLs pero ninguna es de tipo Deny."
            }
        } else {
            Write-WARN "No hay ACLs para admin_storage en OU Cuates."
        }
    } catch {
        Write-ERR "Error leyendo ACLs admin_storage: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando que admin_auditoria este en Event Log Readers..."
    try {
        $grupos = Get-ADPrincipalGroupMembership -Identity "admin_auditoria" | Select-Object -ExpandProperty Name
        if ($grupos -contains "Event Log Readers") {
            Write-OK "admin_auditoria: CORRECTO - pertenece a Event Log Readers"
        } else {
            Write-WARN "admin_auditoria NO esta en Event Log Readers. Ejecuta la opcion 2."
        }
    } catch {
        Write-ERR "Error verificando grupos: $($_.Exception.Message)"
    }

    Pause-Menu
}

function Test-FGPP {
    Write-Banner
    Write-Host "  TEST 2 - VERIFICACION DE FGPP (CONTRASENA INSUFICIENTE)" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "FGPPs configuradas en el dominio:"
    try {
        Get-ADFineGrainedPasswordPolicy -Filter * |
            Select-Object Name, Precedence, MinPasswordLength, LockoutThreshold, LockoutDuration |
            Format-Table -AutoSize
    } catch {
        Write-ERR "Error leyendo FGPPs: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Politica efectiva para admin_identidad..."
    try {
        $pol = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad"
        if ($pol) {
            Write-OK "Politica efectiva encontrada:"
            Write-Host "  Nombre    : $($pol.Name)" -ForegroundColor Green
            Write-Host "  MinLength : $($pol.MinPasswordLength) caracteres" -ForegroundColor Green
            Write-Host "  Lockout   : $($pol.LockoutThreshold) intentos" -ForegroundColor Green
        } else {
            Write-WARN "Sin FGPP aplicada a admin_identidad. Aplica Default Domain Policy."
        }
    } catch {
        Write-ERR "Error obteniendo politica efectiva: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Intentando asignar contrasena de 8 caracteres a admin_identidad (debe ser rechazada)..."
    try {
        $passCorta = ConvertTo-SecureString "Pass1234" -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $passCorta -Reset -ErrorAction Stop
        Write-ERR "FALLO DEL TEST: La contrasena de 8 chars fue aceptada. Verifica la FGPP."
    } catch {
        $errMsg = $_.Exception.Message
        Write-OK "TEST EXITOSO: El sistema rechazo la contrasena corta."
        Write-Host "  Mensaje del sistema: $errMsg" -ForegroundColor DarkGray
    }

    Pause-Menu
}

function Test-MFA {
    Write-Banner
    Write-Host "  TEST 3 - VERIFICACION DE MFA Y CREDENTIAL PROVIDER" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Write-INFO "Credential Providers registrados en el sistema..."
    $cpKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
    try {
        $providers = Get-ChildItem $cpKey
        Write-Host ""
        Write-Host "  Lista de Credential Providers activos:" -ForegroundColor Yellow
        foreach ($p in $providers) {
            $nombre = (Get-ItemProperty -Path $p.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $guid   = $p.PSChildName
            Write-Host "  [$guid] $nombre"
        }

        $mfaCP = $providers | Where-Object {
            $n = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $n -like "*Google*" -or $n -like "*TOTP*" -or $n -like "*Auth*" -or $n -like "*MFA*" -or $n -like "*OTP*"
        }

        Write-Host ""
        if ($mfaCP) {
            Write-OK "Credential Provider de MFA/TOTP detectado:"
            $mfaCP | ForEach-Object {
                $n = (Get-ItemProperty -Path $_.PSPath)."(Default)"
                Write-Host "  -> $n ($($_.PSChildName))" -ForegroundColor Green
            }
        } else {
            Write-WARN "No se detecto Credential Provider de MFA/TOTP."
            Write-WARN "Instala el Credential Provider usando la opcion 6 del menu."
            Write-Host ""
            Write-INFO "Para verificar MFA manualmente:"
            Write-Host "  1. Cierra sesion en el servidor"
            Write-Host "  2. En la pantalla de login debe aparecer campo para codigo TOTP"
            Write-Host "  3. Abre Google Authenticator y usa el codigo de 6 digitos"
        }
    } catch {
        Write-ERR "Error leyendo Credential Providers: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-INFO "Verificando clave TOTP almacenada en AD para admin_identidad..."
    try {
        $userInfo = Get-ADUser -Identity "admin_identidad" -Properties info -ErrorAction SilentlyContinue
        if ($userInfo -and $userInfo.info -like "TOTP_SECRET:*") {
            Write-OK "admin_identidad tiene clave TOTP en AD"
        } else {
            Write-WARN "admin_identidad no tiene clave TOTP. Usa la opcion 6 > D para generarla."
        }
    } catch {
        Write-WARN "No se pudo leer atributo TOTP de AD."
    }

    Pause-Menu
}

function Test-Bloqueo {
    Write-Banner
    Write-Host "  TEST 4 - SIMULACION DE BLOQUEO POR FALLOS CONSECUTIVOS" -ForegroundColor White
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $usuarioPrueba = Read-Host "  Usuario a probar (ENTER para usar usr_cuate01)"
    if ([string]::IsNullOrWhiteSpace($usuarioPrueba)) { $usuarioPrueba = "usr_cuate01" }

    Write-WARN "Se realizaran 4 intentos fallidos de autenticacion."
    Write-WARN "Esto puede bloquear la cuenta '$usuarioPrueba' por 30 minutos."
    $confirma = Read-Host "  Confirmar? (S/N)"
    if ($confirma -ne "S" -and $confirma -ne "s") { Pause-Menu; return }

    Write-Host ""
    Write-INFO "Simulando intentos fallidos de autenticacion..."

    1..4 | ForEach-Object {
        try {
            $domainLdap = "LDAP://$($Global:Dominio)"
            $entry = New-Object System.DirectoryServices.DirectoryEntry(
                $domainLdap,
                $usuarioPrueba,
                "ContrasenaIncorrecta$_!"
            )
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
            $searcher.FindOne() | Out-Null
        } catch {
            $errShort = $_.Exception.Message.Split("`n")[0]
            Write-WARN "Intento $_ fallido: $errShort"
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host ""
    Write-INFO "Verificando estado de la cuenta '$usuarioPrueba'..."
    Start-Sleep -Seconds 2

    try {
        $usr = Get-ADUser -Identity $usuarioPrueba `
            -Properties LockedOut, BadLogonCount, BadPasswordTime, PasswordLastSet

        Write-Host ""
        Write-Host "  Estado de la cuenta '$usuarioPrueba':" -ForegroundColor White
        $colorLocked = if ($usr.LockedOut) { "Green" } else { "Yellow" }
        Write-Host "  LockedOut      : $($usr.LockedOut)" -ForegroundColor $colorLocked
        Write-Host "  BadLogonCount  : $($usr.BadLogonCount)"
        Write-Host "  BadPasswordTime: $($usr.BadPasswordTime)"
        Write-Host ""

        if ($usr.LockedOut) {
            Write-OK "TEST EXITOSO: La cuenta quedo bloqueada - LockedOut = True"
        } else {
            Write-WARN "La cuenta NO esta bloqueada aun."
            $badCount = $usr.BadLogonCount
            Write-WARN "BadLogonCount = $badCount (revisa el threshold de la FGPP)"
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
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    Ensure-LogDir
    $reporteFile = "$($Global:LogPath)\Reporte_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $sep  = "=" * 70
    $sep2 = "-" * 40
    $lineas = @()

    $lineas += $sep
    $lineas += " REPORTE DE ESTADO - PRACTICA 09 - AD HARDENING / RBAC / MFA"
    $lineas += " Generado : $(Get-Date)"
    $lineas += " Servidor : $env:COMPUTERNAME"
    $lineas += " Dominio  : $($Global:Dominio)"
    $lineas += $sep

    # Usuarios delegados
    $lineas += ""
    $lineas += "USUARIOS DELEGADOS:"
    $lineas += $sep2
    foreach ($u in @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
        try {
            $usr = Get-ADUser -Identity $u -Properties Description, Enabled, LockedOut -ErrorAction Stop
            $lineas += "  $($usr.SamAccountName) | Enabled=$($usr.Enabled) | Locked=$($usr.LockedOut)"
        } catch {
            $lineas += "  $u -> NO ENCONTRADO"
        }
    }

    # FGPPs
    $lineas += ""
    $lineas += "DIRECTIVAS FGPP:"
    $lineas += $sep2
    try {
        Get-ADFineGrainedPasswordPolicy -Filter * | ForEach-Object {
            $lineas += "  $($_.Name) | Prec=$($_.Precedence) | MinLen=$($_.MinPasswordLength) | Lockout=$($_.LockoutThreshold) | Dur=$($_.LockoutDuration)"
        }
    } catch {
        $lineas += "  Error leyendo FGPPs"
    }

    # Auditoria
    $lineas += ""
    $lineas += "AUDITORIA (subcategorias relevantes):"
    $lineas += $sep2
    $audOutput = & auditpol /get /category:* 2>&1
    $audFiltrado = $audOutput | Where-Object { $_ -match "Logon|Object Access|Account|Policy Change" }
    $lineas += $audFiltrado

    # Credential Providers
    $lineas += ""
    $lineas += "CREDENTIAL PROVIDERS REGISTRADOS:"
    $lineas += $sep2
    try {
        $cpKey3 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
        Get-ChildItem $cpKey3 | ForEach-Object {
            $n = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue)."(Default)"
            $lineas += "  [$($_.PSChildName)] $n"
        }
    } catch {
        $lineas += "  Error leyendo Credential Providers"
    }

    # Eventos 4625
    $lineas += ""
    $lineas += "ULTIMOS 5 EVENTOS 4625:"
    $lineas += $sep2
    try {
        $ev4625 = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 5 -ErrorAction SilentlyContinue
        if ($ev4625) {
            foreach ($e in $ev4625) {
                $uEvt = try { $e.Properties[5].Value  } catch { "N/A" }
                $iEvt = try { $e.Properties[19].Value } catch { "N/A" }
                $lineas += "  $($e.TimeCreated) | Usuario: $uEvt | IP: $iEvt"
            }
        } else {
            $lineas += "  Sin eventos 4625"
        }
    } catch {
        $lineas += "  Error leyendo eventos de seguridad"
    }

    $lineas += ""
    $lineas += $sep

    $lineas | ForEach-Object { Write-Host "  $_" }
    $lineas | Out-File $reporteFile -Encoding UTF8
    Write-Host ""
    Write-OK "Reporte guardado en: $reporteFile"

    Pause-Menu
}

# ============================================================
#  MENU PRINCIPAL
# ============================================================

function Show-MenuPrincipal {
    Write-Banner
    Write-Host "  Dominio  : $($Global:Dominio)" -ForegroundColor DarkGray
    Write-Host "  Servidor : $env:COMPUTERNAME"  -ForegroundColor DarkGray
    Write-Host "  Logs en  : $($Global:LogPath)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --- BLOQUE 1: DELEGACION Y RBAC ----------------------------" -ForegroundColor DarkYellow
    Write-Host "  [1] Crear usuarios administradores delegados (4 roles)"
    Write-Host "  [2] Configurar ACLs y permisos granulares (dsacls)"
    Write-Host ""
    Write-Host "  --- BLOQUE 2: DIRECTIVAS Y AUDITORIA -----------------------" -ForegroundColor DarkYellow
    Write-Host "  [3] Crear FGPP - min 12 chars admins / 8 chars usuarios"
    Write-Host "  [4] Habilitar auditoria de eventos"
    Write-Host "  [5] Ejecutar script de monitoreo (exportar eventos 4625)"
    Write-Host ""
    Write-Host "  --- BLOQUE 3: MFA GOOGLE AUTHENTICATOR --------------------" -ForegroundColor DarkYellow
    Write-Host "  [6] Configurar MFA TOTP (Credential Provider)"
    Write-Host "  [7] Configurar bloqueo - 3 fallos / 30 min"
    Write-Host ""
    Write-Host "  --- BLOQUE 4: VERIFICACION ---------------------------------" -ForegroundColor DarkYellow
    Write-Host "  [8] Menu de tests (protocolo de pruebas completo)"
    Write-Host ""
    Write-Host "  [9] CONFIGURACION COMPLETA (bloques 1-3 en orden)"
    Write-Host "  [0] Salir"
    Write-Host ""
    $opcion = Read-Host "  Selecciona una opcion"
    return $opcion
}

# ============================================================
#  PUNTO DE ENTRADA
# ============================================================

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator"
)
if (-not $esAdmin) {
    Write-Host ""
    Write-Host "  [ERROR] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    Write-Host "  Clic derecho sobre PowerShell -> Ejecutar como administrador" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Presiona ENTER para salir"
    exit 1
}

if (-not (Test-ADModuleLoaded)) {
    Write-Host ""
    Write-Host "  [ERROR] Modulo ActiveDirectory no disponible." -ForegroundColor Red
    Write-Host "  Ejecuta: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    Read-Host "  Presiona ENTER para salir"
    exit 1
}

Ensure-LogDir

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
            Write-OK "Configuracion completa finalizada. Usa la opcion 6 para MFA."
            Pause-Menu
        }
        "0" {
            Write-Host ""
            Write-Host "  Saliendo de Practica 09." -ForegroundColor DarkGray
            Write-Host "  Logs y reportes en: $($Global:LogPath)" -ForegroundColor DarkGray
            Write-Host ""
        }
        default {
            Write-WARN "Opcion no valida. Elige entre 0 y 9."
            Start-Sleep -Seconds 1
        }
    }
} while ($opcion -ne "0")
