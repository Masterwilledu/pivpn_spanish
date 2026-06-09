#!/usr/bin/env bash
# PiVPN: Script de Copia de Respaldo (Backup)
# Herramienta automatizada para la exportación y empaquetado seguro de perfiles y llaves criptográficas.

export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# ==============================================================================
#                 CONFIGURACIÓN DE GEOMETRÍA Y CONSTANTES DE ENTORNO
# ==============================================================================

# Detección dinámica de las dimensiones de la terminal para ajustar los diálogos gráficos
screen_size="$(stty size 2> /dev/null || echo 24 80)"
rows="$(echo "${screen_size}" | awk '{print $1}')"
columns="$(echo "${screen_size}" | awk '{print $2}')"

# Escala proporcional para cuadros de diálogo (50% de la pantalla actual)
r=$((rows / 2))
c=$((columns / 2))

# Límites mínimos de holgura para prevenir deformaciones visuales en pantallas pequeñas
r=$((r < 20 ? 20 : r))
c=$((c < 70 ? 70 : c))

# Definición de directivas de rutas del ecosistema de respaldo
backupdir="pivpnbackup"
date="$(date +%Y%m%d-%H%M%S)"
setupVarsFile="setupVars.conf"
setupConfigDir="/etc/pivpn"

CHECK_PKG_INSTALLED='dpkg-query -s'

# ==============================================================================
#                            FUNCIONES AUXILIARES
# ==============================================================================

err() {
  echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ::: [ERROR] $*" >&2
}

checkbackupdir() {
  # Validación de seguridad: Asegurar que las variables de entorno de la instalación están cargadas
  # shellcheck disable=SC2154
  if [[ -z "${install_home}" ]]; then
    err "La variable de entorno '\${install_home}' está vacía o corrupta. No se puede determinar la ruta destino."
    exit 1
  fi

  # Intento de creación del árbol de directorios persistente
  if ! mkdir -p "${install_home}/${backupdir}"; then
    err "Fallo crítico de E/S: Imposible instanciar el directorio de copias en: ${install_home}/${backupdir}"
    exit 1
  fi
}

backup_openvpn() {
  local openvpndir="/etc/openvpn"
  local ovpnsdir="${install_home}/ovpns"
  local backupzip="${date}-pivpnovpnbackup.tgz"
  local tar_err_log="/tmp/pivpn_tar_err.log"

  checkbackupdir
  echo "::: [INFO] Iniciando el empaquetado criptográfico del entorno OpenVPN..."

  # Compresión atómica evaluando la salida del binario tar de forma explícita
  # shellcheck disable=SC2154
  if ! tar -czf "${install_home}/${backupdir}/${backupzip}" \
    "${openvpndir}/easy-rsa/pki" \
    "${openvpndir}/server.conf" \
    "${ovpnsdir}" \
    "${setupConfigDir}/openvpn/${setupVarsFile}" 2> "${tar_err_log}"; then
    
    echo ":::" >&2
    err "No se pudo completar el empaquetado comprimido de OpenVPN. Detalles del sistema:"
    cat "${tar_err_log}" >&2
    rm -f "${tar_err_log}"
    exit 1
  fi

  rm -f "${tar_err_log}"
  echo "::: [ÉXITO] El respaldo de OpenVPN se ha consolidado correctamente."
  echo "::: [INFO] Ubicación del archivo generado: ${install_home}/${backupdir}/${backupzip}"
}

backup_wireguard() {
  local wgdir="/etc/wireguard"
  local backupzip="${date}-pivpnwgbackup.tgz"
  local tar_err_log="/tmp/pivpn_tar_err.log"

  checkbackupdir
  echo "::: [INFO] Iniciando el empaquetado criptográfico del entorno WireGuard..."

  # Compresión atómica evaluando la salida del binario tar de forma explícita
  # shellcheck disable=SC2154
  if ! tar -czf "${install_home}/${backupdir}/${backupzip}" \
    "${wgdir}/wg0.conf" \
    "${wgdir}/keys" \
    "${install_home}/configs" \
    "${setupConfigDir}/wireguard/${setupVarsFile}" 2> "${tar_err_log}"; then
    
    echo ":::" >&2
    err "No se pudo completar el empaquetado comprimido de WireGuard. Detalles del sistema:"
    cat "${tar_err_log}" >&2
    rm -f "${tar_err_log}"
    exit 1
  fi

  rm -f "${tar_err_log}"
  echo "::: [ÉXITO] El respaldo de WireGuard se ha consolidado correctamente."
  echo "::: [INFO] Ubicación del archivo generado: ${install_home}/${backupdir}/${backupzip}"
}

# ==============================================================================
#                         FLUJO PRINCIPAL DE EJECUCIÓN
# ==============================================================================

# Escenario A: Coexistencia Multiprotocolo detectada en el sistema local
if [[ -r "${setupConfigDir}/wireguard/${setupVarsFile}" ]] \
  && [[ -r "${setupConfigDir}/openvpn/${setupVarsFile}" ]]; then

  # Si el script fue invocado con argumentos posicionales por CLI, priorizamos esa vía
  if [[ "$#" -ge 1 ]]; then
    VPN="${1}"
    echo "::: [INFO] Parámetro de entrada CLI detectado. Procesando respaldo para la instancia: ${VPN}"
  else
    # Lanzamiento del asistente interactivo Whiptail optimizado en español
    chooseVPNCmd=(whiptail
      --backtitle "Asistente de Respaldo - PiVPN"
      --title "Múltiples Instancias Detectadas"
      --ok-button "Seleccionar"
      --cancel-button "Cancelar"
      --separate-output
      --radiolist "Se han encontrado configuraciones activas tanto para OpenVPN como para WireGuard.\n\nPor favor, seleccione cuál de ellas desea respaldar en este lote (use la barra espaciadora para marcar su opción):"
      "${r}" "${c}" 2)
    
    VPNChooseOptions=(
      "WireGuard" "Instancia criptográfica basada en tunelización UDP rápida" on
      "OpenVPN" "Instancia clásica basada en SSL/TLS estándar" off
    )

    # Captura segura de la selección interactiva mapeando interrupciones (ESC / Cancelar)
    if ! VPN="$("${chooseVPNCmd[@]}" "${VPNChooseOptions[@]}" 2>&1 > /dev/tty)"; then
      echo ":::"
      err "Operación abortada por el usuario o interrupción de interfaz gráfica (ESC)."
      exit 1
    fi
    
    echo "::: [INFO] Procesando la solicitud seleccionada por interfaz: ${VPN}"
    VPN="${VPN,,}"
  fi

  setupVars="${setupConfigDir}/${VPN}/${setupVarsFile}"

# Escenario B: Monoprotocolo. Identificación y enrutamiento automático de la instancia existente
else
  echo "::: [INFO] Analizando topología de red local..."
  if [[ -r "${setupConfigDir}/wireguard/${setupVarsFile}" ]]; then
    echo "::: [INFO] Entorno dedicado exclusivo de WireGuard localizado."
    setupVars="${setupConfigDir}/wireguard/${setupVarsFile}"
    VPN="wireguard"
  elif [[ -r "${setupConfigDir}/openvpn/${setupVarsFile}" ]]; then
    echo "::: [INFO] Entorno dedicado exclusivo de OpenVPN localizado."
    setupVars="${setupConfigDir}/openvpn/${setupVarsFile}"
    VPN="openvpn"
  fi
fi

# Validación final de existencia de la metadata estructurada del servidor
if [[ ! -f "${setupVars}" ]]; then
  err "Fallo de consistencia: El archivo de variables fundamentales '${setupVars}' no existe o no es legible."
  exit 1
fi

echo "::: [INFO] Cargando variables de entorno dinámicas del servidor PiVPN..."
# shellcheck disable=SC1090
source "${setupVars}"

# Ajuste de comandos de paquetería para compatibilidad de distribuciones (Parche Alpine Linux)
if [[ "${PLAT}" == 'Alpine' ]]; then
  CHECK_PKG_INSTALLED='apk --no-cache info -e'
fi

# Derivación definitiva al motor de compresión correspondiente
if [[ "${VPN}" == "wireguard" ]]; then
  backup_wireguard
elif [[ "${VPN}" == "openvpn" ]]; then
  backup_openvpn
else
  err "Tipo de VPN inválido o desconocido ('${VPN}'). Imposible procesar el lote de respaldo."
  exit 1
fi