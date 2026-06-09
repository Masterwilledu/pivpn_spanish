#!/usr/bin/env bash
# PiVPN: Script para Habilitar Perfiles de Clientes WireGuard
# Revierte la suspensión comentada en wg0.conf y restaura el acceso del peer en caliente.

export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# ==============================================================================
#                 VALIDACIONES PREVENTIVAS Y CONTROL DE PRIVILEGIOS
# ==============================================================================

setupVars="/etc/pivpn/wireguard/setupVars.conf"

err() {
  echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ::: [ERROR] $*" >&2
}

# Comprobación de existencia del archivo base de configuración
if [[ ! -f "${setupVars}" ]]; then
  err "Falta el archivo de variables de configuración indispensable en: ${setupVars}"
  exit 1
fi

# shellcheck disable=SC1090
source "${setupVars}"

# El script requiere interactuar con el servicio WireGuard y modificar ficheros en /etc
if [[ "${EUID}" -ne 0 ]]; then
  err "Este script requiere privilegios de acceso raíz (root). Intente usar 'sudo'."
  exit 1
fi

# ==============================================================================
#                            MANUAL DE USO (HELP)
# ==============================================================================

helpFunc() {
  echo "::: [INFO] Asistente de Reactivación de Clientes - PiVPN Spanish"
  echo ":::"
  echo "::: Uso: pivpn <-on|on> [-h|--help] [-y|--yes] [-v] [cliente-1 cliente-2 ...]"
  echo ":::"
  echo "::: Comandos y Opciones:"
  echo ":::   [Ninguno]       Invoca el modo interactivo con interfaz visual (Whiptail)."
  echo ":::   <cliente>       Especifica el nombre o índice del cliente a habilitar."
  echo ":::   -y, --yes       Habilita los clientes provistos de forma directa sin confirmación."
  echo ":::   -v              Lista exclusivamente los usuarios que se encuentran deshabilitados."
  echo ":::   -h, --help      Muestra este diálogo informativo de ayuda."
}

# ==============================================================================
#                      PROCESAMIENTO DE ARGUMENTOS CLI
# ==============================================================================

CLIENTS_TO_CHANGE=()

while [[ "$#" -gt 0 ]]; do
  case "${1}" in
    -h | --help)
      helpFunc
      exit 0
      ;;
    -y | --yes)
      CONFIRM=true
      ;;
    -v)
      DISPLAY_DISABLED=true
      ;;
    *)
      CLIENTS_TO_CHANGE+=("${1}")
      ;;
  esac
  shift
done

cd /etc/wireguard || { err "No se pudo acceder al directorio /etc/wireguard"; exit 1; }

# Validación de la base de datos local de clientes registrados
if [[ ! -s configs/clients.txt ]]; then
  err "La base de datos de clientes está vacía o no existe (configs/clients.txt)."
  exit 1
fi

# Procesamiento inmediato de la bandera de visualización pasiva (-v)
if [[ "${DISPLAY_DISABLED}" == "true" ]]; then
  echo "::: [INFO] Listado de clientes actualmente deshabilitados en el sistema:"
  if ! grep -q '\[disabled\] ### begin' wg0.conf; then
    echo "  (Ninguno - Todos los perfiles están activos)"
  else
    grep '\[disabled\] ### begin' wg0.conf | sed -E 's/(\[disabled\]|###|begin|#)//g' | awk '{print "  • " $1}'
  fi
  exit 0
fi

# Mapeo nativo en memoria de la lista general de clientes registrados
mapfile -t FULL_LIST < <(awk '{print $1}' configs/clients.txt)

# ==============================================================================
#             MODO INTERACTIVO: ASISTENTE VISUAL VIA WHIPTAIL
# ==============================================================================

if [[ "${#CLIENTS_TO_CHANGE[@]}" -eq 0 ]]; then
  # Detección y dimensionamiento de la terminal anfitriona
  screen_size="$(stty size 2> /dev/null || echo 24 80)"
  rows="$(echo "${screen_size}" | awk '{print $1}')"
  columns="$(echo "${screen_size}" | awk '{print $2}')"
  
  r=$((rows / 2))
  c=$((columns / 2))
  r=$((r < 20 ? 20 : r))
  c=$((c < 70 ? 70 : c))

  WHIPTAIL_OPTIONS=()
  for client in "${FULL_LIST[@]}"; do
    # Identificar de forma proactiva si el cliente está actualmente suspendido
    if grep -q "#\[disabled\] ### begin ${client} ###" wg0.conf; then
      WHIPTAIL_OPTIONS+=("${client}" "[Deshabilitado]" "OFF")
    else
      WHIPTAIL_OPTIONS+=("${client}" "[Ya Activo]" "OFF")
    fi
  done

  # Construcción dinámica de la TUI (Interfaz de Usuario de Terminal)
  chooseCmd=(whiptail
    --backtitle "Ecosistema de Gestión PiVPN"
    --title "Reactivar Perfiles de Clientes"
    --ok-button "Habilitar"
    --cancel-button "Salir"
    --separate-output
    --checklist "Seleccione con la tecla [Espacio] el o los clientes que desea reactivar:\n(Presione [Intro] para aplicar los cambios)"
    "${r}" "${c}" 10)

  if selex="$("${chooseCmd[@]}" "${WHIPTAIL_OPTIONS[@]}" 2>&1 > /dev/tty)"; then
    mapfile -t CLIENTS_TO_CHANGE <<< "${selex}"
  else
    echo "::: [INFO] Operación cancelada por el usuario. Saliendo sin aplicar cambios..."
    exit 0
  fi

  if [[ "${#CLIENTS_TO_CHANGE[@]}" -eq 0 || -z "${CLIENTS_TO_CHANGE[0]}" ]]; then
    echo "::: [INFO] No seleccionó ningún cliente para modificar. Finalizando..."
    exit 0
  fi
  
  # Al venir de la interfaz gráfica, se asume consentimiento explícito de lotes
  CONFIRM=true
fi

# ==============================================================================
#                 PROCESAMIENTO Y APLICACIÓN DE CAMBIOS (SED)
# ==============================================================================

CHANGED_COUNT=0
re_numeric='^[0-9]+$'

for TARGET_CLIENT in "${CLIENTS_TO_CHANGE[@]}"; do
  # Omitir entradas vacías accidentales
  [[ -z "${TARGET_CLIENT}" ]] && continue

  # Mapeo de índices numéricos heredados del modo CLI clásico
  if [[ "${TARGET_CLIENT}" =~ ${re_numeric} ]]; then
    TARGET_CLIENT="${FULL_LIST[$((TARGET_CLIENT - 1))]}"
  fi

  # Verificaciones de integridad por cada elemento del lote
  if ! grep -q "^${TARGET_CLIENT} " configs/clients.txt; then
    echo -e "::: [ADVERTENCIA] El cliente \e[1m${TARGET_CLIENT}\e[0m no figura en el registro de credenciales."
  elif ! grep -q "#\[disabled\] ### begin ${TARGET_CLIENT} ###" wg0.conf; then
    echo -e "::: [INFO] El cliente \e[1m${TARGET_CLIENT}\e[0m ya se encuentra activo y operativo en el servidor."
  else
    # Confirmación en consola si no se especificó el flag automático (-y)
    if [[ -z "${CONFIRM}" ]]; then
      read -r -p "::: ¿Confirmas que deseas reactivar al cliente '${TARGET_CLIENT}'? [S/n]: " REPLY
      # Acepta 'S', 's', 'Y', 'y' o un retorno de carro directo (Enter como afirmación)
      if [[ ! "${REPLY}" =~ ^[SsYy]?$ ]]; then
        echo "::: [INFO] Operación omitida para el cliente '${TARGET_CLIENT}'."
        continue
      fi
    fi

    # Mutación segura del archivo de configuración descomentando el bloque del peer
    sed_pattern="/### begin ${TARGET_CLIENT} ###/,"
    sed_pattern="${sed_pattern}/### end ${TARGET_CLIENT} ###/ s/#\[disabled\] //"
    
    if sed -e "${sed_pattern}" -i wg0.conf; then
      echo "::: [OK] Estructura de red restaurada para: ${TARGET_CLIENT}"
      ((CHANGED_COUNT++))
    else
      err "No se pudo escribir sobre el archivo de configuración para el cliente: ${TARGET_CLIENT}"
    fi
    unset sed_pattern
  fi
done

# ==============================================================================
#                     RELOAD RESTRICCIONADO DE SERVICIOS
# ==============================================================================

if [[ "${CHANGED_COUNT}" -gt 0 ]]; then
  echo "::: [INFO] Sincronizando alteraciones con las tablas activas del Kernel..."
  
  if [[ "${PLAT}" == 'Alpine' ]]; then
    if rc-service wg-quick restart &>/dev/null; then
      echo "::: [ÉXITO] El motor de WireGuard ha sido reiniciado en Alpine."
    else
      err "Fallo crítico al reiniciar la interfaz mediante rc-service."
    fi
  else
    if systemctl reload wg-quick@wg0 &>/dev/null; then
      echo "::: [ÉXITO] La tabla de enrutamiento de WireGuard ha sido recargada correctamente."
    else
      err "Fallo crítico al recargar la interfaz a través de systemctl."
    fi
  fi
else
  echo "::: [INFO] Sincronización finalizada sin alteraciones en el servicio de red."
fi

exit 0