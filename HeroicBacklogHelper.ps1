# -*- coding: utf-8 -*-
# --- Configuración de Codificación Interna ---
# ASEGÚRATE DE GUARDAR ESTE ARCHIVO COMO UTF-8 con BOM
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
# !!! AJUSTA ESTA RUTA SI TU CACHÉ DE HEROIC ESTÁ EN OTRO LUGAR !!!
$directorioHeroic = Join-Path -Path $env:APPDATA -ChildPath "heroic\store_cache" # Forma más robusta de obtener AppData
# $directorioHeroic = "C:\Users\onita\AppData\Roaming\heroic\store_cache" # Alternativa manual si la anterior falla

if (-not (Test-Path -Path $directorioHeroic -PathType Container)) {
    Write-Error "El directorio especificado no existe: $directorioHeroic"
    Write-Error "Verifica la variable `$directorioHeroic` en el script."
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

function GenerarListaCompleta {
    Write-Host "Generando la lista completa de juegos..."
    $archivoSalida = ".\lista_juegos_completa.txt"
    $tab = "`t"; $huboErroresJq = $false
    # Asegurar que el archivo se cree/vacíe con la codificación correcta
    Set-Content -Path $archivoSalida -Value "" -Encoding UTF8

    $tiendas = @(
        @{ Nombre="EPIC";   Json=".\legendary_library.json"; Runner="legendary"; Filtro='.library[] | select(.runner == $runnerName) | .title' }
        @{ Nombre="GOG";    Json=".\gog_library.json";        Runner="gog";       Filtro='.games[] | select(.runner == $runnerName) | .title' }
        @{ Nombre="AMAZON"; Json=".\nile_library.json";       Runner="nile";      Filtro='.library[] | select(.runner == $runnerName) | .title' }
    )

    foreach ($tienda in $tiendas) {
        if (Test-Path $tienda.Json) {
            Write-Host "Procesando $($tienda.Nombre) ($($tienda.Json))..."
            $resultados = $null # Inicializar resultados
            try {
                # ### CORRECCIÓN ###: Se eliminó "-ErrorAction Stop" de la llamada a jq.
                # Ejecutamos jq y capturamos su salida estándar (stdout).
                $resultados = (& $jqExecutable -r --arg runnerName $tienda.Runner $tienda.Filtro $tienda.Json)

                # ### CORRECCIÓN ###: Verificar el código de salida de jq inmediatamente.
                if ($LASTEXITCODE -ne 0) {
                    # Lanzamos un error de PowerShell si jq falló.
                    Throw "jq falló con código de salida $LASTEXITCODE. Verifica la salida de error de jq si está visible."
                }

                # Si jq tuvo éxito ($LASTEXITCODE fue 0)
                if ($resultados -and $resultados.Length -gt 0) {
                    # Añadir resultados al archivo
                    $resultados | ForEach-Object { "$_$($tab)$($tienda.Nombre)" } | Add-Content -Path $archivoSalida -Encoding UTF8
                    Write-Host " -> Juegos de $($tienda.Nombre) procesados OK." -ForegroundColor Green
                } else {
                    # jq funcionó pero no encontró juegos con ese runner
                     Write-Host " -> No se encontraron juegos para $($tienda.Nombre) (runner '$($tienda.Runner)')." -ForegroundColor Yellow
                }

            } catch {
                # Capturamos el error lanzado por 'Throw' o cualquier otro error de PowerShell (ej. acceso a archivos)
                Write-Warning "Error procesando $($tienda.Json): $($_.Exception.Message)"
                $huboErroresJq = $true
                # Los $resultados de esta tienda serán null o incompletos, no se añadirán.
            }
        } else {
            Write-Warning "Archivo no encontrado: $($tienda.Json)"
        }
    } # Fin foreach tienda

    # Reporte final
    if ($huboErroresJq) { Write-Warning "Se encontraron errores al usar jq. Lista '$archivoSalida' podría estar incompleta." }
    else {
        if ((Test-Path $archivoSalida) -and (Get-Item $archivoSalida).Length -gt 0) { Write-Host "Lista completa generada/actualizada en '$archivoSalida'." -ForegroundColor Cyan }
        elseif (Test-Path $archivoSalida) { Write-Host "Archivos procesados, sin juegos encontrados o añadidos a '$archivoSalida'." -ForegroundColor Yellow }
        else { Write-Warning "No se pudo crear/escribir en '$archivoSalida'." } # Esto no debería ocurrir si Set-Content inicial funcionó
    }
} # Fin function GenerarListaCompleta

function ComprobarNuevosJuegos {
    Write-Host "Comprobando nuevos juegos..."
    $archivoCompleto = ".\lista_juegos_completa.txt"
    $archivoBacklog = ".\yaenbacklog.txt"
    $archivoNuevos = ".\nuevos_juegos.txt"

    if (-not (Test-Path $archivoCompleto)) { Write-Warning "Archivo '$archivoCompleto' no existe. Ejecuta la opción 1 primero."; return }
    if (-not (Test-Path $archivoBacklog)) { Write-Warning "Archivo '$archivoBacklog' no existe. Creando vacío."; Set-Content -Path $archivoBacklog -Value "" -Encoding UTF8 }

    try {
        # Usar -Raw para leer el archivo completo, luego dividir. Es más seguro con líneas vacías.
        $listaCompletaContent = Get-Content $archivoCompleto -Encoding UTF8 -Raw -ErrorAction Stop
        $yaEnBacklogContent = Get-Content $archivoBacklog -Encoding UTF8 -Raw -ErrorAction Stop

        # Dividir por nueva línea y quitar líneas vacías resultantes
        $listaCompleta = $listaCompletaContent -split '(\r?\n)' | Where-Object { $_.Trim() -ne '' }
        $yaEnBacklog = $yaEnBacklogContent -split '(\r?\n)' | Where-Object { $_.Trim() -ne '' }

        # ### CORRECCIÓN ###: Verificar si $listaCompleta es null o vacía antes de Compare-Object
        if ($null -eq $listaCompleta -or $listaCompleta.Length -eq 0) {
             Write-Warning "La lista '$archivoCompleto' está vacía o no se pudo leer. ¿La opción 1 se ejecutó correctamente y encontró juegos?"
             # Si existe el archivo de nuevos anterior, eliminarlo para evitar confusiones
             if (Test-Path $archivoNuevos) { Remove-Item $archivoNuevos; Write-Host "Archivo '$archivoNuevos' anterior eliminado."}
             return # Salir de la función si no hay lista completa
        }

        # Si $yaEnBacklog está vacío (primera ejecución), Compare-Object lo maneja, pero inicializar a array vacío es más limpio
        if ($null -eq $yaEnBacklog) {
            $yaEnBacklog = @()
        }

        # Compara: busca elementos en $listaCompleta que NO están en $yaEnBacklog
        # SideIndicator indica en qué lista está el elemento diferente ('=>' para DifferenceObject)
        $juegosNuevosObj = Compare-Object -ReferenceObject $yaEnBacklog -DifferenceObject $listaCompleta -IncludeEqual:$false
        $juegosNuevos = $juegosNuevosObj | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject

        if ($juegosNuevos -and $juegosNuevos.Length -gt 0) {
            $numNuevos = $juegosNuevos.Length
            Write-Host "Se han encontrado $numNuevos juego(s) nuevo(s):" -ForegroundColor Green
            $juegosNuevos | ForEach-Object { Write-Host "  + $_" -ForegroundColor White }
            # Guardar los juegos nuevos, asegurando codificación UTF8
            $juegosNuevos | Out-File -FilePath $archivoNuevos -Encoding UTF8
            Write-Host "Guardados en '$archivoNuevos'." -ForegroundColor Green
        } else {
            Write-Host "No se encontraron juegos nuevos." -ForegroundColor Yellow
            if (Test-Path $archivoNuevos) { Remove-Item $archivoNuevos; Write-Host "Archivo '$archivoNuevos' anterior eliminado." }
        }
    } catch {
        # ### CORRECCIÓN ###: Mensaje de error más específico
        Write-Error "Error durante la comprobación/lectura de archivos: $($_.Exception.Message)"
        Write-Error "Asegúrate de que los archivos '$archivoCompleto' y '$archivoBacklog' existen y no están bloqueados."
    }
} # Fin function ComprobarNuevosJuegos

function AnadirNuevosAlBacklog {
    Write-Host "Añadiendo nuevos juegos al backlog..."
    $archivoNuevos = ".\nuevos_juegos.txt"
    $archivoBacklog = ".\yaenbacklog.txt"

    if (Test-Path $archivoNuevos) {
        $juegosParaAnadir = Get-Content $archivoNuevos -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }

        if ($juegosParaAnadir -and $juegosParaAnadir.Length -gt 0) {
             Write-Host "Se añadirán los siguientes $($juegosParaAnadir.Length) juego(s) a '$archivoBacklog':" -ForegroundColor Cyan
             $juegosParaAnadir | ForEach-Object { Write-Host "  -> $_" -ForegroundColor White }
             try {
                 if (-not (Test-Path $archivoBacklog)) { Write-Warning "Archivo '$archivoBacklog' no existe. Creándolo."; Set-Content -Path $archivoBacklog -Value "" -Encoding UTF8 }
                 # Usar Add-Content asegura que se añada al final y mantiene codificación si existe
                 $juegosParaAnadir | Add-Content -Path $archivoBacklog -Encoding UTF8 -ErrorAction Stop
                 Remove-Item $archivoNuevos
                 Write-Host "Juegos añadidos a '$archivoBacklog'. Archivo '$archivoNuevos' eliminado." -ForegroundColor Green
             } catch { Write-Error "Error al añadir a '$archivoBacklog': $($_.Exception.Message)" }
        } else {
             Write-Host "'$archivoNuevos' está vacío. No hay nada que añadir." -ForegroundColor Yellow
             Remove-Item $archivoNuevos # Eliminar aunque esté vacío
             Write-Host "Archivo '$archivoNuevos' (vacío) eliminado."
        }
    } else {
        Write-Host "No hay archivo '$archivoNuevos'. Ejecuta la opción 2 primero y asegúrate de que encontró juegos nuevos." -ForegroundColor Yellow
    }
} # Fin function AnadirNuevosAlBacklog

# --- Menú principal ---
$salir = $false
do {
    # Usar Write-Output puede ser ligeramente más compatible con la codificación a veces
    Write-Output "`n--- Menú de Gestión de Backlog ---"
    Write-Output "1. Generar lista completa (sobrescribe lista_juegos_completa.txt)"
    Write-Output "2. Comprobar nuevos juegos (compara con yaenbacklog.txt)"
    Write-Output "3. Añadir nuevos al backlog (mueve nuevos_juegos.txt a yaenbacklog.txt)"
    Write-Output "4. Salir"

    $opcion = $null
    try {
        $opcion = Read-Host "Selecciona una opción (1-4)"
    } catch {
        Write-Error "No se pudo leer la entrada. ¿El script se está ejecutando de forma no interactiva?"
        $salir = $true # Salir si no podemos obtener entrada
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

# Pausa final opcional si se ejecutó directamente
if (-not $Host.Name.Contains("ConsoleHost") -and !$PSISE -and (-not $env:WT_SESSION)) { # Evitar pausa en Windows Terminal también
    Write-Output "`nEjecución completada. Presiona Enter para cerrar."
    Read-Host
}