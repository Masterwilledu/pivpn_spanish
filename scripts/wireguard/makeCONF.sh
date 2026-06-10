#!/usr/bin/env bash
# PiVPN: Módulo Complementario de Generación de Perfiles de Cliente (WireGuard)
# Optimizado para entornos interactivos con trazabilidad avanzada y soporte UTF-8 nativo.

export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# ==============================================================================
#          CÁLCULO DINÁMICO DE RESOLUCIÓN PARA INTERFACES WHIPTAIL
# ==============================================================================
# Captura la geometría de la terminal actual; en entornos no interactivos, asume 24x80.
screen_size="$(stty size 2> /dev/null || echo "24 80")"
read -r rows columns <<< "${screen_size}"

# Dimensionamiento adaptativo proporcional al 50% de la pantalla actual.
r=$(( rows / 2 ))
c=$(( columns / 2 ))

# Márgenes de seguridad mínimos exigidos para evitar truncamiento de botones y diálogos.
[[ ${r} -lt 20 ]] && r=20
[[ ${c} -lt 70 ]] && c=70

# ==============================================================================
#                 CONFIGURACIÓN DE RUTAS Y VARIABLES GLOBALES
# ==============================================================================
# Inicialización preventiva de variables de verificación para mitigar errores de referencia vacía.
pivpnPERSISTENTKEEPALIVE=""
pivpnDNS2=""

setupVars="/etc/pivpn/wireguard/setupVars.conf"

echo ":::"
echo "::: [INFO] Cargando variables de entorno del servidor e identificando recursos de red..."

if [[ ! -f "${setupVars}" ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERROR CRÍTICO]: No se localizó el archivo de variables esenciales en '${setupVars}'." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${setupVars}"

if [[ ! -r /opt/pivpn/ipaddr_utils.sh ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERROR CRÍTICO]: No se puede leer el archivo de utilidades primarias '/opt/pivpn/ipaddr_utils.sh'." >&2
    exit 1
fi
# shellcheck disable=SC1091
source /opt/pivpn/ipaddr_utils.sh

# Asignación segura del grupo operativo del sistema
# shellcheck disable=SC2154
userGroup="${install_user}:${install_user}"

# ==============================================================================
#                       FUNCIONES COMPLEMENTARIAS Y DIAGNÓSTICO
# ==============================================================================
err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] [ERROR]: $*" >&2
}

helpFunc() {
    echo "::: [AYUDA] Generador de Perfiles de Cliente VPN"
    echo ":::"
    echo "::: Uso: pivpn <-a|add> [-n|--name <nombre>] [-ip|--client-ip <ipv4>] [-h|--help]"
    echo ":::"
    echo "::: Opciones y Comandos disponibles:"
    echo ":::   [ninguno]            Inicia el asistente en modo interactivo (Gráfico/Terminal)"
    echo ":::   -n, --name           Asigna un nombre al cliente (Valor predeterminado: '${HOSTNAME}')"
    echo ":::   -ip, --client-ip     Fuerza una dirección IPv4 específica ('auto' para asignación automática)"
    echo ":::   -h, --help           Muestra este panel de ayuda descriptivo"
}

checkName() {
    # Validación exhaustiva de cumplimiento de reglas de red y sistemas de archivos para nombres de clientes
    if [[ -z "${CLIENT_NAME}" ]]; then
        echo "::: [AVISO] El campo de nombre se encuentra en blanco. Asignando valor del sistema: '${HOSTNAME}'."
        CLIENT_NAME="${HOSTNAME}"
    fi

    if [[ "${CLIENT_NAME}" =~ [^a-zA-Z0-9.@_-] ]]; then
        err "El nombre '${CLIENT_NAME}' contiene caracteres inválidos. Solo se admiten valores alfanuméricos y símbolos seguros (.-@_)."
        exit 1
    elif [[ "${CLIENT_NAME}" =~ ^[0-9]+$ ]]; then
        err "Regla de nomenclatura infringida: El nombre de cliente no puede estar compuesto únicamente por números enteros."
        exit 1
    elif [[ "${CLIENT_NAME}" =~ \ |\' ]]; then
        err "Regla de nomenclatura infringida: No se admiten espacios en blanco ni comillas en el identificador."
        exit 1
    elif [[ "${CLIENT_NAME:0:1}" == "-" ]]; then
        err "Regla de nomenclatura infringida: El nombre del cliente no puede dar inicio con un guion (-)."
        exit 1
    elif [[ "${CLIENT_NAME:0:1}" == "." ]]; then
        err "Regla de nomenclatura infringida: El nombre del cliente no puede dar inicio con un punto (.)."
        exit 1
    elif [[ "${#CLIENT_NAME}" -gt 15 ]]; then
        err "Restricción de longitud: El nombre excede el límite máximo de 15 caracteres (Longitud provista: ${#CLIENT_NAME})."
        exit 1
    elif [[ "${CLIENT_NAME}" == "server" ]]; then
        err "Colisión de nombres de sistema: El término 'server' está estrictamente reservado para el nodo maestro de la VPN."
        exit 1
    elif [[ -f "configs/${CLIENT_NAME}.conf" ]]; then
        err "Conflicto de redundancia: Ya existe un perfil de cliente con el identificador '${CLIENT_NAME}.conf' en este servidor."
        exit 1
    fi
    echo "::: [INFO] Identificador de cliente validado correctamente: '${CLIENT_NAME}'."
}

checkClientIP() {
    local ip ipv4_regex
    ip="$1"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"

    if [[ ! "${ip}" =~ $ipv4_regex ]]; then
        err "Formato de red inválido: La dirección IP '${ip}' provista no cumple con la estructura estándar IPv4."
        exit 1
    fi
}

# ==============================================================================
#                 ANÁLISIS DE PARÁMETROS DE ENTRADA (CLI PARSER)
# ==============================================================================
echo "::: [INFO] Iniciando el procesamiento de argumentos pasados por consola..."

while [[ "$#" -gt 0 ]]; do
    _key="${1}"

    case "${_key}" in
        -n | --name | --name=*)
            _val="${_key##--name=}"

            if [[ "${_val}" == "${_key}" ]]; then
                [[ "$#" -lt 2 ]] \
                    && err "Falta el valor requerido para el parámetro de entrada '${_key}'." \
                    && exit 1

                _val="${2}"
                shift
            fi

            CLIENT_NAME="${_val}"
            checkName
            ;;
        -ip | --client-ip | --client-ip=*)
            _val="${_key##--client-ip=}"

            if [[ "${_val}" == "${_key}" ]]; then
                [[ "$#" -lt 2 ]] \
                    && err "Falta el valor requerido para el parámetro de entrada '${_key}'." \
                    && exit 1

                _val="${2}"
                shift
            fi

            CLIENT_IP="${_val}"
            ;;
        -h | --help)
            helpFunc
            exit 0
            ;;
        *)
            err "Error: Argumento inesperado o desconocido detectado en el flujo: '${1}'"
            helpFunc
            exit 1
            ;;
    esac
    shift
done

# ==============================================================================
#            AUDITORÍA DE ESPACIO DE TRABAJO Y ASIGNACIÓN DE RED
# ==============================================================================
# Verificación y aprovisionamiento seguro de directorios locales de almacenamiento
# shellcheck disable=SC2154
if [[ ! -d "${install_home}/configs" ]]; then
    echo "::: [INFO] Estructura ausente: Creando repositorio centralizado de perfiles en '${install_home}/configs'..."
    if mkdir -p "${install_home}/configs"; then
        chown "${userGroup}" "${install_home}/configs"
        chmod 0750 "${install_home}/configs"
        echo "::: [ÉXITO] Directorio de configuraciones aprovisionado con permisos restrictivos de seguridad (0750)."
    else
        err "Fallo crítico de permisos: No se pudo consolidar la estructura de directorios requerida."
        exit 1
    fi
fi

if ! cd /etc/wireguard 2>/dev/null; then
    err "Fallo de entorno: No se pudo mover la terminal al directorio de control de WireGuard (/etc/wireguard)."
    exit 1
fi

# Asegura la existencia del archivo de mapeo para evitar errores de lectura con comandos internos
touch configs/clients.txt

# Excluye del cálculo la dirección de ID de red, dirección de broadcast y la interfaz propia del servidor
# shellcheck disable=SC2154
MAX_CLIENTS="$((2 ** (32 - subnetClass) - 3))"
CURRENT_CLIENTS_COUNT="$(wc -l < configs/clients.txt)"

if [[ "${CURRENT_CLIENTS_COUNT}" -ge "${MAX_CLIENTS}" ]]; then
    err "Capacidad de subred agotada: No se pueden agregar más clientes. El límite estructural es de ${MAX_CLIENTS} dispositivos (Activos: ${CURRENT_CLIENTS_COUNT})."
    exit 1
fi

# shellcheck disable=SC2154
NETID_IPV4_DEC="$(dotIPv4FirstDec "${pivpnNET}" "${subnetClass}")"
BROADCAST_IPV4_DEC="$(dotIPv4LastDec "${pivpnNET}" "${subnetClass}")"

FIRST_IPV4_DEC=$((NETID_IPV4_DEC + 2))
LAST_IPV4_DEC=$((BROADCAST_IPV4_DEC - 1))
FIRST_IPV4="$(decIPv4ToDot "${FIRST_IPV4_DEC}")"
LAST_IPV4="$(decIPv4ToDot "${LAST_IPV4_DEC}")"

# ------------------------------------------------------------------------------
# INTERFAZ INTERACTIVA: ASIGNACIÓN DE DIRECCIÓN IP DEL CLIENTE
# ------------------------------------------------------------------------------
if [[ -z "${CLIENT_IP}" ]]; then
    if [[ -t 0 ]] && command -v whiptail >/dev/null 2>&1; then
        CLIENT_IP="$(whiptail \
            --backtitle "Asistente de Configuración PiVPN - WireGuard" \
            --title "Direccionamiento IP del Cliente" \
            --ok-button "Continuar" \
            --cancel-button "Asignación Automática" \
            --inputbox "Introduce la dirección IPv4 local asignada de forma estática para este perfil de cliente.\n\nRango operativo válido dentro de tu subred:\n➡ ${FIRST_IPV4} hasta ${LAST_IPV4}\n\n(Deja vacío o cancela este diálogo para autodetectar la primera dirección disponible):" "${r}" "${c}" \
            3>&1 1>&2 2>&3)"
        
        # Si el usuario presiona Cancelar o lo deja en blanco, se asume autodetectado de forma transparente.
        [[ $? -ne 0 || -z "${CLIENT_IP}" ]] && CLIENT_IP="auto"
    else
        read -r -p "::: Introduce la IP del Cliente del rango [${FIRST_IPV4} - ${LAST_IPV4}] (Opcional, ENTER para auto): " CLIENT_IP
        [[ -z "${CLIENT_IP}" ]] && CLIENT_IP="auto"
    fi
fi

if [[ -n "${CLIENT_IP}" && "${CLIENT_IP}" != "auto" ]]; then
    checkClientIP "${CLIENT_IP}"
    ip="$(dotIPv4ToDec "${CLIENT_IP}")"

    if [[ "${ip}" -lt "${FIRST_IPV4_DEC}" || "${ip}" -gt "${LAST_IPV4_DEC}" ]]; then
        err "Desbordamiento de segmento: La IP provista '${CLIENT_IP}' está fuera de los límites de la máscara de red [${FIRST_IPV4} - ${LAST_IPV4}]."
        exit 1
    fi

    if ! grep -q " ${ip}$" configs/clients.txt; then
        UNUSED_IPV4_DEC="${ip}"
        echo "::: [INFO] Asignando dirección IP fija reservada explícitamente: '$(decIPv4ToDot "${ip}")'."
    else
        err "Conflicto de red: La dirección IP '${CLIENT_IP}' ya se encuentra registrada y en uso por otro dispositivo en 'configs/clients.txt'."
        exit 1
    fi
else
    # Algoritmo lineal secuencial para el descubrimiento automático de direcciones IPs disponibles
    echo "::: [INFO] Buscando de forma automatizada un direccionamiento IPv4 huérfano dentro de la subred..."
    UNUSED_IPV4_DEC=""
    for ((ip = FIRST_IPV4_DEC; ip <= LAST_IPV4_DEC; ip++)); do
        if ! grep -q " ${ip}$" configs/clients.txt; then
            UNUSED_IPV4_DEC="${ip}"
            echo "::: [ÉXITO] Dirección IPv4 libre localizada con éxito: '$(decIPv4ToDot "${ip}")'."
            break
        fi
    done

    if [[ -z "${UNUSED_IPV4_DEC}" ]]; then
        err "Agotamiento crítico: No se encontraron direcciones IP libres disponibles en el rango establecido de red."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# INTERFAZ INTERACTIVA: IDENTIFICADOR / NOMBRE DE CLIENTE
# ------------------------------------------------------------------------------
if [[ -z "${CLIENT_NAME}" ]]; then
    if [[ -t 0 ]] && command -v whiptail >/dev/null 2>&1; then
        while true; do
            CLIENT_NAME="$(whiptail \
                --backtitle "Asistente de Configuración PiVPN - WireGuard" \
                --title "Nombre del Perfil de Cliente" \
                --ok-button "Validar y Guardar" \
                --cancel-button "Cancelar Operación" \
                --inputbox "Ingresa un identificador descriptivo único para este dispositivo cliente (ej: MovilEmilia, PortatilCasa).\n\nRestricciones obligatorias de formato:\n• Máximo 15 caracteres de longitud.\n• Sin espacios en blanco.\n• Solo caracteres alfanuméricos y símbolos (.-@_).\n\n(Si se deja en blanco se utilizará por defecto: '${HOSTNAME}'):" "${r}" "${c}" \
                3>&1 1>&2 2>&3)"
            
            if [[ $? -ne 0 ]]; then
                echo ":::"
                err "Operación abortada por orden explícita del administrador del sistema."
                exit 1
            fi
            
            # Saneamiento express: Elimina espacios en blanco introducidos por error
            CLIENT_NAME="${CLIENT_NAME// /}"
            [[ -z "${CLIENT_NAME}" ]] && CLIENT_NAME="${HOSTNAME}"
            
            checkName
            break
        done
    else
        read -r -p "::: Introduce un Nombre identificativo para el Cliente (Por defecto: '${HOSTNAME}'): " CLIENT_NAME
        [[ -z "${CLIENT_NAME}" ]] && CLIENT_NAME="${HOSTNAME}"
        checkName
    fi
else
    # Si fue recibido directamente mediante banderas en la invocación por terminal, ejecuta la validación
    checkName
fi

# ==============================================================================
#                     FINALIZACIÓN DE VALIDACIONES DE PARÁMETROS
# ==============================================================================
echo "::: [ÉXITO] Fase transaccional terminada correctamente."
echo "::: [INFO] Entorno consolidado para compilar el perfil definitivo de '${CLIENT_NAME}' bajo la IP '$(decIPv4ToDot "${UNUSED_IPV4_DEC}")'."