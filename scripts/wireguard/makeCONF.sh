#!/bin/bash

### Constantes
# Algunas variables que podrían estar vacías pero necesitan ser definidas para verificaciones
pivpnPERSISTENTKEEPALIVE=""
pivpnDNS2=""

setupVars="/etc/pivpn/wireguard/setupVars.conf"

# shellcheck disable=SC1090
source "${setupVars}"

if [ ! -r /opt/pivpn/ipaddr_utils.sh ]; then
  exit 1
fi
# shellcheck disable=SC1091
source /opt/pivpn/ipaddr_utils.sh

# shellcheck disable=SC2154
userGroup="${install_user}:${install_user}"

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

helpFunc() {
  echo "::: Crear un perfil de configuración de cliente"
  echo ":::"
  echo "::: Uso: pivpn <-a|add> [-n|--name <arg>] [-ip|--client-ip <ipv4>] [-h|--help]"
  echo ":::"
  echo "::: Comandos:"
  echo ":::  [ninguno]            Modo interactivo"
  echo ":::  -n,--name            Nombre para el Cliente (predeterminado: '${HOSTNAME}')"
  echo ":::  -ip,--client-ip      Dirección IPv4 del Cliente ('auto' para asignar IP automáticamente)"
  echo ":::  -h,--help            Mostrar este diálogo de ayuda"
}

checkName() {
  # comprobar nombre
  if [[ -z "${CLIENT_NAME}" ]]; then
    err "::: El nombre está en blanco. Usando valor predeterminado '${HOSTNAME}'."
    CLIENT_NAME=$HOSTNAME
  fi
  if [[ "${CLIENT_NAME}" =~ [^a-zA-Z0-9.@_-] ]]; then
    err "El nombre solo puede contener caracteres alfanuméricos y estos símbolos (.-@_)."
    exit 1
  elif [[ "${CLIENT_NAME}" =~ ^[0-9]+$ ]]; then
    err "Los nombres no pueden ser números enteros."
    exit 1
  elif [[ "${CLIENT_NAME}" =~ \ |\' ]]; then
    err "Los nombres no pueden contener espacios."
    exit 1
  elif [[ "${CLIENT_NAME:0:1}" == "-" ]]; then
    err "El nombre no puede comenzar con - (guion)"
    exit 1
  elif [[ "${CLIENT_NAME::1}" == "." ]]; then
    err "Los nombres no pueden comenzar con un . (punto)."
    exit 1
  elif [[ "${#CLIENT_NAME}" -gt 15 ]]; then
    err "::: Los nombres no pueden tener más de 15 caracteres."
    exit 1
  elif [[ "${CLIENT_NAME}" == "server" ]]; then
    err "Lo siento, este nombre está en uso por el servidor y no puede ser usado por los clientes."
    exit 1
  elif [[ -f "configs/${CLIENT_NAME}.conf" ]]; then
    err "::: Ya existe un cliente con este nombre."
    exit 1
  fi
}

checkClientIP() {
  local ip ipv4_regex
  ip="$1"
  ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}"
  ipv4_regex+="(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"

  if [[ ! "${ip}" =~ $ipv4_regex ]]; then
    err "::: IP inválida: ${ip}"
    exit 1
  fi
}

### Script
if [[ ! -f "${setupVars}" ]]; then
  err "::: ¡Falta el archivo de variables de configuración!"
  exit 1
fi

# Analizar argumentos de entrada
while [[ "$#" -gt 0 ]]; do
  _key="${1}"

  case "${_key}" in
    -n | --name | --name=*)
      _val="${_key##--name=}"

      if [[ "${_val}" == "${_key}" ]]; then
        [[ "$#" -lt 2 ]] \
          && err "::: Falta valor para el argumento opcional '${_key}'." \
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
          && err "::: Falta valor para el argumento opcional '${_key}'." \
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
      err "::: Error: Se recibió un argumento inesperado '${1}'"
      helpFunc
      exit 1
      ;;
  esac

  shift
done

# Deshabilitando SC2154, variables cargadas externamente
# shellcheck disable=SC2154
# La variable de la carpeta de inicio se cargó desde el archivo de configuración.
if [[ ! -d "${install_home}/configs" ]]; then
  mkdir "${install_home}/configs"
  chown "${userGroup}" "${install_home}/configs"
  chmod 0750 "${install_home}/configs"
fi

cd /etc/wireguard || exit

# Excluir la primera, última y la dirección del servidor
# shellcheck disable=SC2154
MAX_CLIENTS="$((2 ** (32 - subnetClass) - 3))"

if [ "$(wc -l configs/clients.txt | awk '{print $1}')" -ge "${MAX_CLIENTS}" ]; then
  echo "::: ¡No se pueden añadir más clientes (máx. ${MAX_CLIENTS})!"
  exit 1
fi

# shellcheck disable=SC2154
NETID_IPV4_DEC="$(dotIPv4FirstDec "${pivpnNET}" "${subnetClass}")"
BROADCAST_IPV4_DEC="$(dotIPv4LastDec "${pivpnNET}" "${subnetClass}")"

FIRST_IPV4_DEC=$((NETID_IPV4_DEC + 2))
LAST_IPV4_DEC=$((BROADCAST_IPV4_DEC - 1))
FIRST_IPV4="$(decIPv4ToDot "${FIRST_IPV4_DEC}")"
LAST_IPV4="$(decIPv4ToDot "${LAST_IPV4_DEC}")"

if [[ -z "${CLIENT_IP}" ]]; then
  read -p "Introduce la IP del Cliente del rango ${FIRST_IPV4} - ${LAST_IPV4} (opcional): " CLIENT_IP
fi

if [[ -n "${CLIENT_IP}" && "${CLIENT_IP}" != "auto" ]]; then
  checkClientIP "${CLIENT_IP}"
  ip="$(dotIPv4ToDec "${CLIENT_IP}")"

  if [[ "${ip}" -lt "${FIRST_IPV4_DEC}" || "${ip}" -gt "${LAST_IPV4_DEC}" ]]; then
    err "::: La IP especificada ${CLIENT_IP} no está en el rango ${FIRST_IPV4} - ${LAST_IPV4}"
    exit 1
  fi

  if ! grep -q " ${ip}$" configs/clients.txt; then
    UNUSED_IPV4_DEC="${ip}"
  else
    err "::: La dirección IP ${CLIENT_IP} ya está en uso"
    exit 1
  fi
else
  # Encontrar una dirección no utilizada para la IP del cliente
  for ((ip = FIRST_IPV4_DEC; ip <= LAST_IPV4_DEC; ip++)); do
    if ! grep -q " ${ip}$" configs/clients.txt; then
      UNUSED_IPV4_DEC="${ip}"
      echo "::: IP de Cliente elegida: $(decIPv4ToDot "${ip}")"
      break
    fi
  done
fi

if [[ -z "${CLIENT_NAME}" ]]; then
  read -r -p "Introduce un Nombre para el Cliente (predeterminado: '${HOSTNAME}'): " CLIENT_NAME
  checkName
else
  check
