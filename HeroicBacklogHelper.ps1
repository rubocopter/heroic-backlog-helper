# -*- coding: utf-8 -*-
# --- Configuración de Codificación Interna ---
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Verificación inicial de jq ---
$jqPath = Get-Command jq -ErrorAction SilentlyContinue
if (-not $jqPath) {
    Write-Error "Error: El comando 'jq' no se encuentra. Asegúrate de que jq esté instalado y añadido a la variable de entorno PATH."
    Write-Error "Puedes descargarlo desde: https://jqlang.github.io/jq/download/"
    if (-not $Host.UI.RawUI.KeyAvailable) { Read-Host "Presiona Enter para salir" }
    exit 1
} else {
    $jqExecutable = $jqPath.Source
    Write-Host "jq encontrado en: $jqExecutable" -ForegroundColor Green
}

# --- Configuración del Directorio ---
$directorioHeroic = "C:\Users\onita\AppData\Roaming\heroic\store_cache" # Ajusta si es necesario

if (-not (Test-Path -Path $directorioHeroic -PathType Container)) {
    Write-Error "El directorio especificado no existe: $directorioHeroic"
    if (-not $Host.UI.RawUI.KeyAvailable) { Read-Host "Presiona Enter para salir" }
    exit 1
}

try {
    Set-Location -Path $directorioHeroic -ErrorAction Stop
    Write-Host "Cambiado al directorio: $(Get-Location)"
} catch {
    Write-Error "No se pudo cambiar al directorio: $directorioHeroic. Error: $($_.Exception.Message)"
    if (-not $Host.UI.RawUI.KeyAvailable) { Read-Host "Presiona Enter para salir" }
    exit 1
}

# --- Funciones ---

# --- FUNCIÓN MODIFICADA ---
function GenerarListaCompleta {
    Write-Host "Generando la lista completa de juegos..."
    $archivoSalida = ".\lista_juegos_completa.txt"
    $tab = "`t"; $huboErroresJq = $false
    Set-Content -Path $archivoSalida -Value "" -Encoding UTF8

    $tiendas = @(
        @{ Nombre="EPIC";   Json=".\legendary_library.json"; Runner="legendary"; Filtro='.library[] | select(.runner == $runnerName) | .title' }
        @{ Nombre="GOG";    Json=".\gog_library.json";        Runner="gog";       Filtro='.games[] | select(.runner == $runnerName) | .title' }
        @{ Nombre="AMAZON"; Json=".\nile_library.json";       Runner="nile";      Filtro='.library[] | select(.runner == $runnerName) | .title' }
    )

    foreach ($tienda in $tiendas) {
        if (Test-Path $tienda.Json) {
            Write-Host "Procesando $($tienda.Nombre) ($($tienda.Json))..."
            try {
                # Llamar a jq y capturar su salida estándar
                $resultados = (& $jqExecutable -r --arg runnerName $tienda.Runner $tienda.Filtro $tienda.Json)

                # Comprobar código de salida de jq
                if ($LASTEXITCODE -ne 0) {
                    # Si jq falló, lanzar un error para que lo capture el catch
                    throw "jq.exe falló al procesar '$($tienda.Json)' con código de salida $LASTEXITCODE."
                }

                # Procesar los resultados si jq tuvo éxito ($LASTEXITCODE fue 0)
                if ($resultados) {
                    if ($resultados -isnot [array]){ $resultados = @($resultados) }
                    $resultados | ForEach-Object { "$_$($tab)$($tienda.Nombre)" } | Add-Content -Path $archivoSalida -Encoding UTF8
                    Write-Host " -> $($resultados.Length) Juego(s) de $($tienda.Nombre) procesados OK." -ForegroundColor Green
                } else {
                     # Esto ahora significa que jq funcionó pero no encontró coincidencias
                     Write-Host " -> No se encontraron juegos para $($tienda.Nombre) (runner '$($tienda.Runner)')." -ForegroundColor Yellow
                }
            } catch {
                # Captura errores de PowerShell o el error que lanzamos si $LASTEXITCODE no era 0.
                Write-Warning "Error procesando $($tienda.Json): $($_.Exception.Message)"
                $huboErroresJq = $true
            }
        } else {
            Write-Warning "Archivo no encontrado: $($tienda.Json)"
        }
    }

    # Reporte final
    if ($huboErroresJq) { Write-Warning "Se encontraron errores al usar jq. Lista '$archivoSalida' podría estar incompleta." }
    else {
        if ((Test-Path $archivoSalida) -and (Get-Item $archivoSalida).Length -gt 0) { Write-Host "Lista completa generada/actualizada en '$archivoSalida'." -ForegroundColor Cyan }
        elseif (Test-Path $archivoSalida) { Write-Host "Archivos procesados, sin juegos nuevos encontrados para añadir a '$archivoSalida'." -ForegroundColor Yellow }
        else { Write-Warning "No se pudo crear/escribir en '$archivoSalida'." }
    }
}
# --- FIN FUNCIÓN MODIFICADA ---


function ComprobarNuevosJuegos {
    Write-Host "Comprobando nuevos juegos..."
    $archivoCompleto = ".\lista_juegos_completa.txt"
    $archivoBacklog = ".\yaenbacklog.txt"
    $archivoNuevos = ".\nuevos_juegos.txt"

    if (-not (Test-Path $archivoCompleto)) { Write-Warning "Archivo '$archivoCompleto' no existe. Opción 1 primero."; return }
    if (-not (Test-Path $archivoBacklog)) { Write-Warning "Archivo '$archivoBacklog' no existe. Creando vacío."; Set-Content -Path $archivoBacklog -Value "" -Encoding UTF8 }

    $juegosNuevos = @()
    if ((Test-Path $archivoCompleto) -and (Test-Path $archivoBacklog)) {
        try {
            $listaCompletaContent = Get-Content $archivoCompleto -Encoding UTF8 -Raw
            $yaEnBacklogContent = Get-Content $archivoBacklog -Encoding UTF8 -Raw
            $listaCompleta = $listaCompletaContent -split '(\r?\n)' | Where-Object { $_.Trim() -ne '' }
            $yaEnBacklog = $yaEnBacklogContent -split '(\r?\n)' | Where-Object { $_.Trim() -ne '' }

            if ($null -eq $listaCompleta -or $listaCompleta.Length -eq 0) {
                Write-Host "El archivo '$archivoCompleto' está vacío o no contiene juegos válidos." -ForegroundColor Yellow
            } else {
                 if ($null -eq $yaEnBacklog) { $yaEnBacklog = @() }
                $diffResult = Compare-Object -ReferenceObject $yaEnBacklog -DifferenceObject $listaCompleta -ErrorAction Stop
                $juegosNuevos = $diffResult | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject
            }

            if ($juegosNuevos -and $juegosNuevos.Length -gt 0) {
                if ($juegosNuevos -isnot [array]) { $juegosNuevos = @($juegosNuevos) }
                $numNuevos = $juegosNuevos.Length
                Write-Host "Se han encontrado $numNuevos juego(s) nuevo(s):" -ForegroundColor Green
                $juegosNuevos | ForEach-Object { Write-Host "  + $_" -ForegroundColor White }
                $juegosNuevos | Out-File -FilePath $archivoNuevos -Encoding UTF8
                Write-Host "Guardados en '$archivoNuevos'." -ForegroundColor Green
            } else {
                Write-Host "No se encontraron juegos nuevos." -ForegroundColor Yellow
                if (Test-Path $archivoNuevos) { Remove-Item $archivoNuevos; Write-Host "Archivo '$archivoNuevos' anterior eliminado." }
            }
        } catch { Write-Error "Error durante la comparación: $($_.Exception.Message)" }
    } else { Write-Warning "No se encontraron '$archivoCompleto' o '$archivoBacklog'." }
}

function AnadirNuevosAlBacklog {
    Write-Host "Añadiendo nuevos juegos al backlog..."
    $archivoNuevos = ".\nuevos_juegos.txt"
    $archivoBacklog = ".\yaenbacklog.txt"

    if (Test-Path $archivoNuevos) {
        $juegosParaAnadir = Get-Content $archivoNuevos -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }

        if ($juegosParaAnadir -and $juegosParaAnadir.Length -gt 0) {
             if ($juegosParaAnadir -isnot [array]) { $juegosParaAnadir = @($juegosParaAnadir) }
             Write-Host "Se añadirán los siguientes $($juegosParaAnadir.Length) juego(s) a '$archivoBacklog':" -ForegroundColor Cyan
             $juegosParaAnadir | ForEach-Object { Write-Host "  -> $_" -ForegroundColor White }
             try {
                 if (-not (Test-Path $archivoBacklog)) { Write-Warning "Archivo '$archivoBacklog' no existe. Creándolo."; Set-Content -Path $archivoBacklog -Value "" -Encoding UTF8 }
                 $juegosParaAnadir | Add-Content -Path $archivoBacklog -Encoding UTF8 -ErrorAction Stop
                 Remove-Item $archivoNuevos
                 Write-Host "Juegos añadidos a '$archivoBacklog'. Archivo '$archivoNuevos' eliminado." -ForegroundColor Green
             } catch { Write-Error "Error al añadir a '$archivoBacklog': $($_.Exception.Message)" }
        } else {
             Write-Host "'$archivoNuevos' está vacío. No hay nada que añadir." -ForegroundColor Yellow
             Remove-Item $archivoNuevos
        }
    } else {
        Write-Host "No hay archivo '$archivoNuevos'. Ejecuta la opción 2 primero." -ForegroundColor Yellow
    }
}

# --- Menú principal ---
$salir = $false
do {
    Write-Host "`n--- Menú de Gestión de Backlog ---" -ForegroundColor Yellow
    Write-Host "1. Generar lista completa (sobrescribe lista_juegos_completa.txt)"
    Write-Host "2. Comprobar nuevos juegos (compara con yaenbacklog.txt)"
    Write-Host "3. Añadir nuevos al backlog (mueve nuevos_juegos.txt a yaenbacklog.txt)"
    Write-Host "4. Salir"

    $opcion = $null
    try {
        $opcion = Read-Host "Selecciona una opción (1-4)"
    } catch {
        Write-Error "No se pudo leer la entrada."
        $salir = $true
    }

    if (-not $salir) {
        switch ($opcion) {
            "1" { GenerarListaCompleta }
            "2" { ComprobarNuevosJuegos }
            "3" { AnadirNuevosAlBacklog }
            "4" { Write-Host "Saliendo..."; $salir = $true }
            default { Write-Host "Opción '$opcion' no válida." -ForegroundColor Red }
        }
    }
} while (-not $salir)

# Pausa final si se ejecutó directamente
if (-not $Host.Name.Contains("ConsoleHost") -and !$PSISE) {
    Write-Host "`nEjecución completada. Presiona Enter para cerrar."
    Read-Host
}
