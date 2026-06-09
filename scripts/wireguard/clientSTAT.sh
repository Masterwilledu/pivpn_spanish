#!/usr/bin/env bash
# PiVPN: Script de Diagnóstico Estadístico y Estado de Clientes WireGuard
# Evalúa el consumo de ancho de banda, direccionamiento virtual y marcas de tiempo de los pares.

export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# ==============================================================================
#                 CONFIGURACIÓN DE CONTEXTO Y VALIDACIÓN DE PRIVILEGIOS
# ==============================================================================

CLIENTS_FILE="/etc/wireguard/configs/clients.txt"
WG_INTERFACE="wg0"
WG_CONF_FILE="/etc/wireguard/${WG_INTERFACE}.conf"

err() {
  echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ::: [ERROR] $*" >&2
}

# Verificación preventiva de seguridad perimetral
if [[ "${EUID}" -ne 0 ]]; then
  err "Este script requiere interactuar con el Kernel y necesita privilegios de administrador (root)."
  err "Por favor, ejecute el comando utilizando: sudo pivpn clients"
  exit 1
fi

# Validación de dependencias core antes de formatear salidas
if ! command -v wg &> /dev/null; then
  err "El binario de gestión 'wg' (WireGuard) no está presente o accesible en el sistema."
  exit 1
fi

# ==============================================================================
#                            FUNCIONES PRINCIPALES
# ==============================================================================

scriptusage() {
  echo "::: [INFO] Monitor de Conexiones Activas de Clientes - PiVPN Spanish"
  echo ":::"
  echo "::: Uso del comando: pivpn <-c|clients> [Opciones]"
  echo ":::"
  echo "::: Opciones válidas:"
  echo ":::   [Ninguna]       Muestra las métricas de tráfico en formato legible (M, G, T)."
  echo ":::   -b, bytes       Despliega los valores binarios exactos de transferencia en bytes."
  echo ":::   -h, help        Muestra este panel de ayuda en la terminal."
}

# Formateador de almacenamiento de alta precisión (IEC Metric Format)
hr() {
  if command -v numfmt &> /dev/null; then
    numfmt --to=iec-i --suffix=B "${1}"
  else
    echo "${1}"
  fi
}

listClients() {
  local dump_data
  
  # Captura defensiva de la tabla de estado atómica de WireGuard
  if ! dump_data="$(wg show "${WG_INTERFACE}" dump 2>/dev/null)"; then
    err "No se pudo extraer el estado operativo de la interfaz '${WG_INTERFACE}'."
    err "Verifique que el servicio de la VPN se encuentre activo e iniciado."
    exit 1
  fi

  # Descartar la fila inicial informativa de la interfaz mediante filtrado nativo
  dump_data="$(tail -n +2 <<< "${dump_data}")"

  echo -e "\n\e[1m::: [INFO] Matriz de Clientes Conectados al Servidor :::\e[0m\n"

  {
    # Inyección de metadatos de cabecera formateados con tabulaciones explícitas
    printf "\e[4mNombre del Cliente\e[0m\t\e[4mIP Pública Remota\e[0m\t\e[4mIP Virtual VPN\e[0m\t\e[4mTráfico Recibido\e[0m\t\e[4mTráfico Enviado\e[0m\t\e[4mÚltima Conexión Existente\e[0m\n"

    # Procesamiento nativo y ultra rápido en memoria: Evita el Fork-Bomb de procesos externos
    while read -r pub_key preshared_key remote_ip virtual_ip last_seen bytes_rcvd bytes_sent keepalive; do
      if [[ -n "${pub_key}" ]]; then
        
        # Recuperación optimizada del alias asignado al par criptográfico
        local client_name=""
        if [[ -f "${CLIENTS_FILE}" ]]; then
          client_name="$(grep -F "${pub_key}" "${CLIENTS_FILE}" | awk '{print $1}')"
        fi
        
        # Salvaguarda en caso de huérfanos o llaves manuales sin mapear en la base de datos local
        [[ -z "${client_name}" ]] && client_name="(Llave: ${pub_key:0:6}...)"

        # Limpieza de la máscara CIDR /32 para simplificar la visualización en pantalla
        local clean_vip="${virtual_ip/\/32/}"

        # Selección dinámica del formato de bytes según la preferencia del operador (CLI flag)
        local display_rcvd="${bytes_rcvd}"
        local display_sent="${bytes_sent}"
        if [[ "${HR}" -eq 1 ]]; then
          display_rcvd="$(hr "${bytes_rcvd}")"
          display_sent="$(hr "${bytes_sent}")"
        fi

        # Traducción y formateo localizado de marcas de tiempo Unix
        local connection_time=""
        if [[ "${last_seen}" -ne 0 ]]; then
          connection_time="$(date -d @"${last_seen}" '+%d %b %Y - %H:%M:%S')"
        else
          connection_time="(Sin Conexión)"
        fi

        # Envío unificado al buffer de tabulación estructurado
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
          "${client_name}" \
          "${remote_ip}" \
          "${clean_vip}" \
          "${display_rcvd}" \
          "${display_sent}" \
          "${connection_time}"
      fi
    done <<< "${dump_data}"

  } | column -ts $'\t'
  echo ""

  # Auditoría estética de identidades administrativas en estado de suspensión programada
  if [[ -f "${WG_CONF_FILE}" ]]; then
    if grep -q '\[disabled\] ### begin' "${WG_CONF_FILE}"; then
      echo -e "\e[1m::: [INFO] Perfiles Administrativos Deshabilitados :::\e[0m"
      grep '\[disabled\] ### begin' "${WG_CONF_FILE}" | sed -E 's/(\[disabled\]|###|begin|#)//g' | awk '{print "  • " $1}'
      echo ""
    fi
  fi
}

# ==============================================================================
#                         EJECUCIÓN DEL SCRIPT PRINCIPAL
# ==============================================================================

if [[ ! -s "${CLIENTS_FILE}" ]]; then
  echo "::: [INFO] No se encontraron registros de clientes configurados en el sistema (${CLIENTS_FILE})."
  exit 0
fi

# Selector lógico limpio y sin bucles redundantes basados en llamadas directas
case "${1}" in
  -b | bytes)
    HR=0
    listClients
    ;;
  -h | help)
    scriptusage
    ;;
  "")
    HR=1
    listClients
    ;;
  *)
    echo "::: [ADVERTENCIA] Parámetro inválido o no reconocido: '${1}'."
    scriptusage
    exit 1
    ;;
esac

exit 0