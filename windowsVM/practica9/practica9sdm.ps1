function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

. ".\funciones\ad9.ps1"
. ".\funciones\delegacion9.ps1"
. ".\funciones\politicas9.ps1"
. ".\funciones\MFA9.ps1"

function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "-------------------------------------------------" -BackgroundColor Magenta -ForegroundColor Black
        Write-Host "    Practica 09: Seguridad, Delegacion y MFA     " -ForegroundColor Magenta
        Write-Host "-------------------------------------------------" -BackgroundColor Magenta -ForegroundColor Black
        Write-Host "  [1] Inicializar entorno"
        Write-Host "  [2] Configurar Active Directory"
        Write-Host "  [3] Configurar Delegacion RBAC"
        Write-Host "  [4] Configurar Politicas y Auditoria"
        Write-Host "  [5] Configurar MFA"
        Write-Host "  [6] Salir"
        Write-Host "-------------------------------------------------" -BackgroundColor Magenta -ForegroundColor Black
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Inicializar-Entorno;   Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-AD;         Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-Delegacion; Read-Host "`nEnter para continuar" }
            "4" { Clear-Host; Configurar-Politicas;  Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Configurar-MFA;        Read-Host "`nEnter para continuar" }
            "6" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu