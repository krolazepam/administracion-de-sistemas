$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"
$MULTIOTP_MSI  = "$PSScriptRoot\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\VC_redist.x64.exe"
$CSV_USUARIOS  = "$PSScriptRoot\usuarios_p9.csv"
$RUTA_CLAVES   = "C:\Users\Administrador\claves_mfa.txt"
$DOMINIO_MFA   = "empresa.local"

$ADMINS_MFA = @(
    "Administrador",
    "admin_identidad",
    "admin_storage",
    "admin_politicas",
    "admin_auditoria"
)

function Generar-ClaveTOTP {
    $base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bytes       = New-Object byte[] 20
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $clave = ""
    for ($i = 0; $i -lt 20; $i++) {
        $clave += $base32Chars[$bytes[$i] % 32]
    }
    return $clave
}

function Registrar-Usuario-Token {
    param([string]$Sam)

    $clave = Generar-ClaveTOTP
    & $MULTIOTP_EXE -createga $Sam $clave | Out-Null

    if ($LASTEXITCODE -eq 11) {
        & $MULTIOTP_EXE -set $Sam prefix-pin=0 | Out-Null
        Print-Ok "  $Sam registrado"

        "Usuario: $Sam"                              | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Nombre en GA: $Sam@$DOMINIO_MFA"          | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        "  Clave:        $clave"                     | Out-File $RUTA_CLAVES -Append -Encoding UTF8
        ""                                           | Out-File $RUTA_CLAVES -Append -Encoding UTF8

    } elseif ($LASTEXITCODE -eq 22) {
        Print-Warn "  $Sam ya registrado en multiOTP (se omite)"
    } else {
        Print-Err "  Error al registrar $Sam (codigo: $LASTEXITCODE)"
    }
}


function Instalar-MultiOTP {
    Print-Info "Verificando instalacion de multiOTP..."

    $instalado = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                 Where-Object { $_.DisplayName -like "*multiOTP*" } |
                 Select-Object -First 1

    if ($instalado) {
        Print-Warn "multiOTP ya instalado: $($instalado.DisplayVersion) (se omite)"
        return
    }

    if (-not (Test-Path $VCREDIST_EXE)) {
        Print-Err "No se encontro: $VCREDIST_EXE"
        return
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        return
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}

function Habilitar-RDP {
    Print-Info "Habilitando RDP..."

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value 0

    # Abrir firewall
    Enable-NetFirewallRule -DisplayGroup "Escritorio remoto" -ErrorAction SilentlyContinue

    Print-Ok "RDP habilitado."
}


function Configurar-PermisosRDP {
    Print-Info "Configurando permisos RDP para usuarios delegados..."

    try {
        Add-ADGroupMember -Identity "Usuarios de escritorio remoto" -Members $ADMINS_MFA -ErrorAction Stop
        Print-Ok "Admins agregados al grupo Usuarios de escritorio remoto."
    } catch {
        Print-Warn "Algunos admins ya estaban en el grupo (se omite)."
    }

    foreach ($admin in $ADMINS_MFA) {
        net localgroup "Usuarios de escritorio remoto" "EMPRESA\$admin" /add 2>$null | Out-Null
    }

    $secpolPath = "C:\secpol_mfa.txt"
    $sdbPath    = "C:\secpol_mfa.sdb"

    secedit /export /cfg $secpolPath | Out-Null

    $content = Get-Content $secpolPath

    # Verificar si ya tiene el SID agregado
    if ($content -like "*S-1-5-32-555*") {
        Print-Warn "Politica de inicio de sesion remoto ya configurada (se omite)."
    } else {
        $content = $content -replace `
            "SeRemoteInteractiveLogonRight = \*S-1-5-32-544", `
            "SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555"

        $content | Set-Content $secpolPath
        secedit /configure /db $sdbPath /cfg $secpolPath /quiet | Out-Null
        Print-Ok "Politica de inicio de sesion remoto configurada."
    }

    # Limpiar archivos temporales
    Remove-Item $secpolPath -ErrorAction SilentlyContinue
    Remove-Item $sdbPath    -ErrorAction SilentlyContinue
}


function Configurar-MultiOTP {
    Print-Info "Configurando multiOTP..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Instala primero multiOTP."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3       | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800  | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e"
    Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1
    Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 1
    Print-Ok "Credential Provider configurado."
}


function Registrar-Usuarios-MFA {
    Print-Info "Registrando usuarios en multiOTP..."

    "========== Claves MFA - $DOMINIO_MFA ==========" | Out-File $RUTA_CLAVES -Encoding UTF8
    "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "Instrucciones:" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "  Abre Google Authenticator -> + -> Ingresar clave -> Tipo: Basada en tiempo" | Out-File $RUTA_CLAVES -Append -Encoding UTF8
    "" | Out-File $RUTA_CLAVES -Append -Encoding UTF8

    # Registrar 4 admins
    Write-Host ""
    Print-Info "Registrando administradores..."
    foreach ($sam in $ADMINS_MFA) {
        Registrar-Usuario-Token -Sam $sam
    }

    if (Test-Path $CSV_USUARIOS) {
        Write-Host ""
        Print-Info "Registrando usuarios del CSV..."
        $usuarios = Import-Csv $CSV_USUARIOS
        foreach ($u in $usuarios) {
            Registrar-Usuario-Token -Sam $u.Usuario
        }
    } else {
        Print-Warn "CSV no encontrado, solo se registraron los admins."
    }

    Write-Host ""
    Print-Ok "Claves guardadas en: $RUTA_CLAVES"
    Write-Host ""
    Write-Host "========== Claves generadas ==========" -ForegroundColor Yellow
    Get-Content $RUTA_CLAVES
    Write-Host "======================================" -ForegroundColor Yellow
}


function Configurar-MFA {
    Clear-Host
    Write-Host "========== Configuracion de MFA =========="
    Write-Host ""

    Instalar-MultiOTP
    Write-Host ""
    Habilitar-RDP
    Write-Host ""
    Configurar-PermisosRDP
    Write-Host ""
    Configurar-MultiOTP
    Write-Host ""
    Registrar-Usuarios-MFA

    Write-Host ""
    Print-Ok "MFA configurado correctamente."
    Print-Info "Cada usuario debe agregar su clave a Google Authenticator."
    Print-Info "Las claves estan en: $RUTA_CLAVES"
    Write-Host ""
}