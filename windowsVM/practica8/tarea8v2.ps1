#Requires -RunAsAdministrator

# ==============================================================
#   Gobernanza, Cuotas y Control de Aplicaciones en AD
#   GPO + FSRM + AppLocker + Active Directory
# ==============================================================

# -----------------------------------------------
# VARIABLES GLOBALES
# -----------------------------------------------
$DOMINIO       = "empresa.local"
$DC_PATH       = "DC=empresa,DC=local"
$RUTA_CSV      = "csv8.csv"
$RUTA_PERFILES = "C:\Perfiles"
$PASSWORD      = "P@ssw0rd123!"


# -----------------------------------------------
# FUNCIONES DE APOYO
# -----------------------------------------------
function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Magenta}
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }


# -----------------------------------------------
# INICIALIZAR ENTORNO
#    Instala roles y promueve el servidor a DC
#    Solo se ejecuta una vez. Reinicia el servidor.
# -----------------------------------------------
function inicializarEntorno {
    Print-Info "Instalando roles necesarios..."

    Install-WindowsFeature AD-Domain-Services, FS-Resource-Manager, GPMC `
        -IncludeManagementTools

    Print-Info "Promoviendo servidor a Controlador de Dominio..."

    $passSegura = ConvertTo-SecureString "SafeModeP@ss123!" -AsPlainText -Force

    # -Force es un switch, no acepta $true ni $false
    Install-ADDSForest -DomainName $DOMINIO -DomainNetBiosName "EMPRESA" -InstallDns $true -SafeModeAdministratorPassword $passSegura -Force

    Print-Warn "El servidor se reiniciara. Ejecuta el script de nuevo despues del reinicio."
}


# -----------------------------------------------
# CREAR UOs, GRUPOS Y USUARIOS DESDE CSV
#    El CSV debe tener columnas:
#    Nombre, Apellido, Usuario, Departamento
#    Sin acentos ni caracteres especiales en el CSV
# -----------------------------------------------
function crearEstructuraAD {
    Print-Info "Creando Unidades Organizativas..."

    foreach ($ou in @("Cuates", "NoCuates")) {
        try {
            New-ADOrganizationalUnit -Name $ou -Path $DC_PATH -ErrorAction Stop
            Print-Ok "OU creada: $ou"
        } catch {
            Print-Warn "OU ya existe: $ou"
        }
    }

    Print-Info "Creando grupos de seguridad..."

    foreach ($grupo in @("Cuates", "NoCuates")) {
        try {
            New-ADGroup -Name $grupo `
                -GroupScope    Global `
                -GroupCategory Security `
                -Path          "OU=$grupo,$DC_PATH" `
                -ErrorAction   Stop
            Print-Ok "Grupo creado: $grupo"
        } catch {
            Print-Warn "Grupo ya existe: $grupo"
        }
    }

    Print-Info "Leyendo CSV y creando usuarios..."

    if (-not (Test-Path $RUTA_CSV)) {
        Print-Err "No se encontro el archivo CSV en: $RUTA_CSV"
        return
    }

    $usuarios = Import-Csv $RUTA_CSV
    $pass     = ConvertTo-SecureString $PASSWORD -AsPlainText -Force

    foreach ($u in $usuarios) {
        $ou = if ($u.Departamento -eq "Cuates") {
            "OU=Cuates,$DC_PATH"
        } else {
            "OU=NoCuates,$DC_PATH"
        }

        try {
            New-ADUser `
                -Name              "$($u.Nombre) $($u.Apellido)" `
                -GivenName         $u.Nombre `
                -Surname           $u.Apellido `
                -SamAccountName    $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              $ou `
                -Enabled           $true `
                -ErrorAction       Stop
            Print-Ok "Usuario creado: $($u.Usuario) -> $($u.Departamento)"
        } catch {
            Print-Warn "Usuario ya existe: $($u.Usuario)"
        }

        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
        } catch {
            Print-Warn "El usuario $($u.Usuario) ya esta en el grupo $($u.Departamento)"
        }
    }

    Print-Ok "Estructura AD lista."
}


# -----------------------------------------------
# HORARIOS DE INICIO DE SESION (LOGON HOURS)
#    + GPO para forzar cierre de sesion
#    Cuates:   08:00 - 15:00
#    NoCuates: 15:00 - 02:00 (dia siguiente)
# -----------------------------------------------
function asignarHorarios {
param([string]$Grupo, [int]$HoraInicio, [int]$HoraFin)
 
    # AD guarda LogonHours en UTC. Calculamos el offset automaticamente.
    $offsetHoras = [int][System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).TotalHours
    $inicioUTC   = $HoraInicio - $offsetHoras
    $finUTC      = $HoraFin    - $offsetHoras
 
    Print-Info "Horario '$Grupo': ${HoraInicio}h-${HoraFin}h local -> ${inicioUTC}h-${finUTC}h UTC (offset $offsetHoras h)"
 
    $bytes = [byte[]](,0x00 * 21)
 
    for ($dia = 0; $dia -lt 7; $dia++) {
        # Horas del mismo dia en UTC
        $ini = [Math]::Max($inicioUTC, 0)
        $fin = [Math]::Min($finUTC, 24)
        for ($hora = $ini; $hora -lt $fin; $hora++) {
            $bit = ($dia * 24) + $hora
            $bytes[[Math]::Floor($bit / 8)] = $bytes[[Math]::Floor($bit / 8)] -bor (1 -shl ($bit % 8))
        }
 
        # Horas que pasan la medianoche UTC (ej: finUTC = 34 -> horas 0-10 del dia siguiente)
        if ($finUTC -gt 24) {
            $diaSig = ($dia + 1) % 7
            for ($hora = 0; $hora -lt ($finUTC - 24); $hora++) {
                $bit = ($diaSig * 24) + $hora
                $bytes[[Math]::Floor($bit / 8)] = $bytes[[Math]::Floor($bit / 8)] -bor (1 -shl ($bit % 8))
            }
        }
 
        # Si inicioUTC es negativo empieza en el dia anterior
        if ($inicioUTC -lt 0) {
            $diaAnt = ($dia - 1 + 7) % 7
            for ($hora = (24 + $inicioUTC); $hora -lt 24; $hora++) {
                $bit = ($diaAnt * 24) + $hora
                $bytes[[Math]::Floor($bit / 8)] = $bytes[[Math]::Floor($bit / 8)] -bor (1 -shl ($bit % 8))
            }
        }
    }
 
    Get-ADGroupMember -Identity $Grupo | Where-Object { $_.objectClass -eq "user" } | ForEach-Object {
        Set-ADUser -Identity $_.SamAccountName -Replace @{ logonHours = $bytes }
        Print-Ok "  Horario aplicado: $($_.SamAccountName)"
    }
}

function configurarHorarios {
    # Horarios en hora LOCAL, el script convierte a UTC automaticamente
    asignarHorarios -Grupo "Cuates"   -HoraInicio 8  -HoraFin 15
    asignarHorarios -Grupo "NoCuates" -HoraInicio 15 -HoraFin 26
 
    Print-Info "Creando GPO para forzar cierre de sesion al expirar horario..."
    $nombreGPO = "GPO-Forzar-Logoff"
 
    if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $nombreGPO | Out-Null
        Print-Ok "GPO creada: $nombreGPO"
    } else { Print-Warn "GPO ya existe: $nombreGPO" }
 
    try {
        New-GPLink -Name $nombreGPO -Target $DC_PATH -LinkEnabled Yes -ErrorAction Stop
        Print-Ok "GPO vinculada al dominio."
    } catch { Print-Warn "El vinculo de GPO ya existe." }
 
    Set-GPRegistryValue -Name $nombreGPO `
        -Key "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" `
        -ValueName "EnableForcedLogOff" -Type DWord -Value 1
 
    Print-Ok "Horarios y GPO de logoff forzado configurados."
}


# -----------------------------------------------
# FSRM: CUOTAS Y APANTALLAMIENTO DE ARCHIVOS
#    Cuates:   10 MB (cuota dura)
#    NoCuates:  5 MB (cuota dura)
#    Bloquea: .mp3 .mp4 .avi .exe .msi .bat
# -----------------------------------------------
function configurarFSRM {
    Import-Module FileServerResourceManager -ErrorAction Stop

    Print-Info "Creando plantillas de cuota..."

    # Eliminar plantillas anteriores para crearlas limpias
    Remove-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Confirm:$false -ErrorAction SilentlyContinue
    Remove-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Confirm:$false -ErrorAction SilentlyContinue

    # -SoftLimit es un switch, no acepta $true ni $false
    # Sin -SoftLimit = cuota dura (bloquea cuando se llena)
    New-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Size (10MB)
    Print-Ok "Plantilla creada: Cuota-Cuates (10 MB)"

    New-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Size (5MB)
    Print-Ok "Plantilla creada: Cuota-NoCuates (5 MB)"

    Print-Info "Creando carpetas y aplicando cuotas por usuario..."

    Get-ADGroupMember -Identity "Cuates" | ForEach-Object {
        $ruta = "$RUTA_PERFILES\$($_.SamAccountName)"
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-Cuates"
        Print-Ok "Cuota 10MB -> $ruta"
    }

    Get-ADGroupMember -Identity "NoCuates" | ForEach-Object {
        $ruta = "$RUTA_PERFILES\$($_.SamAccountName)"
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-NoCuates"
        Print-Ok "Cuota 5MB -> $ruta"
    }

    Print-Info "Configurando apantallamiento de archivos..."

    # Eliminar grupo y plantilla anteriores para crearlos limpios
    Remove-FsrmFileGroup        -Name "Archivos-Prohibidos"     -Confirm:$false -ErrorAction SilentlyContinue
    Remove-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos"   -Confirm:$false -ErrorAction SilentlyContinue

    New-FsrmFileGroup -Name "Archivos-Prohibidos" `
        -IncludePattern @("*.mp3","*.mp4","*.avi","*.exe","*.msi","*.bat")
    Print-Ok "Grupo de archivos prohibidos creado."

    # -Active es un switch, no acepta $true ni $false
    New-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -Active -IncludeGroup @("Archivos-Prohibidos")
    Print-Ok "Plantilla de apantallamiento creada."

    Get-ADGroupMember -Identity "Cuates"   | ForEach-Object {
        $ruta = "$RUTA_PERFILES\$($_.SamAccountName)"
        Remove-FsrmFileScreen -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmFileScreen -Path $ruta -Template "Pantalla-Prohibidos"
        Print-Ok "Apantallamiento aplicado: $ruta"
    }

    Get-ADGroupMember -Identity "NoCuates" | ForEach-Object {
        $ruta = "$RUTA_PERFILES\$($_.SamAccountName)"
        Remove-FsrmFileScreen -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmFileScreen -Path $ruta -Template "Pantalla-Prohibidos"
        Print-Ok "Apantallamiento aplicado: $ruta"
    }

    Print-Ok "FSRM configurado correctamente."
}


# -----------------------------------------------
# APPLOCKER
#    Cuates:   PERMITEN notepad.exe (por ruta)
#    NoCuates: BLOQUEAN notepad.exe (por hash SHA256)
#              El hash bloquea aunque renombren el .exe
# -----------------------------------------------
function configurarAppLocker {
    $rutaNotepad = "$env:SystemRoot\System32\notepad.exe"

    if (-not (Test-Path $rutaNotepad)) {
        Print-Err "No se encontro notepad.exe en $rutaNotepad"
        return
    }

    Print-Info "Calculando hash SHA256 de notepad.exe..."
    $info   = Get-AppLockerFileInformation -Path $rutaNotepad
    $hash   = $info.Hash[0].HashDataString
    $tamano = (Get-Item $rutaNotepad).Length

    $sidCuates   = (Get-ADGroup -Identity "Cuates").SID.Value
    $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
    $sidAdmins   = "S-1-5-32-544"

    # GUIDs sin llaves {} porque AppLocker no acepta el formato "B"
    $g1 = [System.Guid]::NewGuid().ToString()
    $g2 = [System.Guid]::NewGuid().ToString()
    $g3 = [System.Guid]::NewGuid().ToString()
    $g4 = [System.Guid]::NewGuid().ToString()

    Print-Info "Generando politica XML de AppLocker..."

    # XML construido con concatenacion para evitar problemas de encoding
    $xml  = "<?xml version=""1.0"" encoding=""utf-8""?>`n"
    $xml += "<AppLockerPolicy Version=""1"">`n"
    $xml += "  <RuleCollection Type=""Exe"" EnforcementMode=""Enabled"">`n"
    $xml += "    <FilePathRule Id=""$g1"" Name=""Admins - permitir todo"" Description=""Administradores sin restricciones"" UserOrGroupSid=""$sidAdmins"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""*""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "    <FilePathRule Id=""$g2"" Name=""Cuates - permitir notepad"" Description=""Cuates pueden usar notepad"" UserOrGroupSid=""$sidCuates"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""%SYSTEM32%\notepad.exe""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "    <FileHashRule Id=""$g3"" Name=""NoCuates - bloquear notepad por hash"" Description=""Bloqueo por hash resiste renombrado"" UserOrGroupSid=""$sidNoCuates"" Action=""Deny"">`n"
    $xml += "      <Conditions>`n"
    $xml += "        <FileHashCondition>`n"
    $xml += "          <FileHash Type=""SHA256"" Data=""$hash"" SourceFileName=""notepad.exe"" SourceFileLength=""$tamano""/>`n"
    $xml += "        </FileHashCondition>`n"
    $xml += "      </Conditions>`n"
    $xml += "    </FileHashRule>`n"
    $xml += "    <FilePathRule Id=""$g4"" Name=""NoCuates - permitir carpeta Windows"" Description=""Permitir ejecucion desde Windows"" UserOrGroupSid=""$sidNoCuates"" Action=""Allow"">`n"
    $xml += "      <Conditions><FilePathCondition Path=""%WINDIR%\*""/></Conditions>`n"
    $xml += "    </FilePathRule>`n"
    $xml += "  </RuleCollection>`n"
    $xml += "</AppLockerPolicy>"

    $rutaXML = "C:\applocker-policy.xml"
    $xml | Out-File $rutaXML -Encoding UTF8
    Print-Ok "XML guardado en $rutaXML"

    $nombreGPO = "GPO-AppLocker"

    if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $nombreGPO | Out-Null
        Print-Ok "GPO creada: $nombreGPO"
    } else {
        Print-Warn "GPO ya existe: $nombreGPO"
    }

    try {
        New-GPLink -Name $nombreGPO -Target $DC_PATH -LinkEnabled Yes -ErrorAction Stop
        Print-Ok "GPO AppLocker vinculada al dominio."
    } catch {
        Print-Warn "Vinculo de GPO ya existe."
    }

    Set-AppLockerPolicy -XMLPolicy $rutaXML -Merge

    # Iniciar servicio AppIDSvc (requerido por AppLocker)
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue

    Print-Ok "AppLocker configurado correctamente."
}


# -----------------------------------------------
# VERIFICACION
#    Revisa el estado de todos los componentes
# -----------------------------------------------
function verificar {
    Write-Host ""
    Write-Host "--- VERIFICACION DEL ENTORNO ---" -ForegroundColor Yellow

    foreach ($ou in @("Cuates","NoCuates")) {
        try {
            Get-ADOrganizationalUnit "OU=$ou,$DC_PATH" | Out-Null
            Print-Ok "OU existe: $ou"
        } catch { Print-Err "OU no encontrada: $ou" }
    }

    foreach ($g in @("Cuates","NoCuates")) {
        $m = Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue
        Print-Info "Grupo $g -> $($m.Count) miembros: $(($m.SamAccountName) -join ', ')"
    }

    $cuotas = Get-FsrmQuota -Path "$RUTA_PERFILES\*" -ErrorAction SilentlyContinue
    Print-Info "Cuotas FSRM activas: $($cuotas.Count)"

    $screens = Get-FsrmFileScreen -Path "$RUTA_PERFILES\*" -ErrorAction SilentlyContinue
    Print-Info "Apantallamientos activos: $($screens.Count)"

    $pol = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
    if ($pol) { Print-Ok "AppLocker: politica efectiva cargada." }
    else       { Print-Err "AppLocker: sin politica efectiva." }

    $svc = Get-Service AppIDSvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq "Running") { Print-Ok "Servicio AppIDSvc: corriendo." }
    else { Print-Warn "Servicio AppIDSvc: $($svc.Status)" }

    foreach ($gpo in @("GPO-Forzar-Logoff","GPO-AppLocker")) {
        if (Get-GPO -Name $gpo -ErrorAction SilentlyContinue) { Print-Ok "GPO existe: $gpo" }
        else { Print-Err "GPO no encontrada: $gpo" }
    }

    $testUser = (Get-ADGroupMember -Identity "NoCuates" | Select-Object -First 1).SamAccountName
    $testFile = "$RUTA_PERFILES\$testUser\test_cuota.bin"
    Print-Info "Probando cuota: escribiendo 6 MB en carpeta de $testUser..."
    try {
        $bytes = [byte[]](,0xFF * (6 * 1MB))
        [System.IO.File]::WriteAllBytes($testFile, $bytes)
        Print-Warn "ALERTA: El archivo se escribio. Revisa la cuota de $testUser."
        Remove-Item $testFile -Force
    } catch {
        Print-Ok "Cuota funciona: escritura de 6 MB bloqueada correctamente."
    }

    Write-Host "--- FIN VERIFICACION ---" -ForegroundColor Yellow
    Write-Host ""
}

function mostrarAlmacenamiento {
    Import-Module FileServerResourceManager

    Get-FsrmQuota -Path "C:\Perfiles\*" | ForEach-Object {
        [PSCustomObject]@{
            Usuario   = Split-Path $_.Path -Leaf
            Plantilla = $_.Template
            LimiteMB  = [Math]::Round($_.Size     / 1MB, 2)
            UsadoMB   = [Math]::Round($_.Usage    / 1MB, 2)
            PicoMB    = [Math]::Round($_.PeakUsage/ 1MB, 2)
            LibreMB   = [Math]::Round(($_.Size - $_.Usage) / 1MB, 2)
            PorcentoUsado = [Math]::Round(($_.Usage / $_.Size) * 100, 1)
        }
    } | Format-Table -AutoSize
}

# -----------------------------------------------
# MENU PRINCIPAL
# -----------------------------------------------
function menuPrincipal {
    do {
        Clear-Host
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        Write-Host "   Gobernanza, Cuotas y Control de             " -ForegroundColor Red
        Write-Host "   Aplicaciones en Active Directory            " -ForegroundColor Red
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        Write-Host "  1. Inicializar entorno  (solo una vez)"
        Write-Host "  2. Crear UOs, grupos y usuarios desde el archivo .CSV"
        Write-Host "  3. Configurar horarios de sesion "
        Write-Host "  4. Configurar FSRM (cuotas + apantallamiento)"
        Write-Host "  5. Configurar bloqueo de apps"
        Write-Host "  6. Verificar entorno"
        Write-Host "  7. Ver estado del almacenamiento"
        Write-Host "  8. Salir"
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { inicializarEntorno;  Read-Host "`nEnter para continuar" }
            "2" { crearEstructuraAD;   Read-Host "`nEnter para continuar" }
            "3" { configurarHorarios;  Read-Host "`nEnter para continuar" }
            "4" { configurarFSRM;      Read-Host "`nEnter para continuar" }
            "5" { configurarAppLocker; Read-Host "`nEnter para continuar" }
            "6" { verificar;           Read-Host "`nEnter para continuar" }
            "7" { mostrarAlmacenamiento; Read-Host "`nEnter para continuar" }
            "8" { Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}


# -----------------------------------------------
# ENTRY POINT
# -----------------------------------------------
menuPrincipal