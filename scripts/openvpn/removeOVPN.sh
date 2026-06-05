#!/bin/bash
# PiVPN: script para revocar cliente

### Constantes
setupVars="/etc/pivpn/openvpn/setupVars.conf"
INDEX="/etc/openvpn/easy-rsa/pki/index.txt"
TC_V2_METADATA="/etc/pivpn/openvpn/tc-v2-metadata.txt"

# shellcheck disable=SC1090
source "${setupVars}"

if [ ! -r /opt/pivpn/ipaddr_utils.sh ]; then
  exit 1
fi
# shellcheck disable=SC1091
source /opt/pivpn/ipaddr_utils.sh

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

helpFunc() {
  echo "::: Revocar un perfil OpenVPN de cliente"
  echo ":::"
  echo -n "::: Uso: pivpn <-r|revoke> [-y|--yes] [-h|--help] "
  echo "[<cliente-1> ... [<cliente-2>] ...]"
  echo ":::"
  echo "::: Comandos:"
  echo ":::  [ninguno]            Modo interactivo"
  echo ":::  <cliente>            Cliente(s) a revocar"
  echo ":::  -y,--yes             Eliminar Cliente(s) sin confirmación"
  echo ":::  -h,--help            Mostrar este diálogo de ayuda"
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
    -h | --help)
      helpFunc
      exit 0
      ;;
    -y | --yes)
      CONFIRM=true
      ;;
    *)
      CERTS_TO_REVOKE+=("${1}")
      ;;
  esac

  shift
done

if [[ ! -f "${INDEX}" ]]; then
  err "No se encontró el archivo: ${INDEX}"
  exit 1
fi

if [[ "${TWO_POINT_FIVE}" -eq 1 ]] && [[ ! -f "${TC_V2_METADATA}" ]]; then
  err "No se encontró el archivo: ${TC_V2_METADATA}"
  exit 1
fi

# Deshabilitando SC2128, solo se verifica si la variable está vacía o no
# shellcheck disable=SC2128
if [[ -z "${CERTS_TO_REVOKE}" ]]; then
  printf "\n"
  printf " ::\e[4m  Lista de Certificados  \e[0m:: \n"

  i=0
  while read -r line || [[ -n "${line}" ]]; do
    STATUS=$(echo "${line}" | awk '{print $1}')

    if [[ "${STATUS}" == "V" ]]; then
      # Deshabilitando advertencia SC2001, el método sugerido no funciona con expresiones regulares
      # shellcheck disable=SC2001
      NAME=$(echo "${line}" | sed -e 's:.*/CN=::')

      if [[ "${i}" != 0 ]]; then
        # Evitar imprimir el certificado del "servidor"
        CERTS["${i}"]=$(echo -e "${NAME}")
      fi

      ((i++))
    fi
  done < "${INDEX}"

  i=1
  len="${#CERTS[@]}"
  while [[ "${i}" -le "${len}" ]]; do
    printf "%0${#len}s) %s\r\n" "${i}" "${CERTS[(($i))]}"
    ((i++))
  done

  printf "\n"
  echo -n "::: Por favor, introduce el Índice/Nombre del cliente a revocar "
  echo -n "de la lista de arriba: "
  read -r NAME

  if [[ -z "${NAME}" ]]; then
    err "¡No puedes dejar esto en blanco!"
    exit 1
  fi

  re='^[0-9]+$'
  if [[ "${NAME}" =~ $re ]]; then
    NAME="${CERTS[$((NAME))]}"
  fi

  for ((x = 1; x <= i; ++x)); do
    if [[ "${CERTS[$x]}" == "${NAME}" ]]; then
      VALID=1
    fi
  done

  if [[ -z "${VALID}" ]]; then
    err "¡No introdujiste un nombre de certificado válido!"
    exit 1
  fi

  CERTS_TO_REVOKE=("${NAME}")
else
  i=0
  while read -r line || [[ -n "${line}" ]]; do
    STATUS=$(echo "${line}" | awk '{print $1}')

    if [[ "${STATUS}" == "V" ]]; then
      NAME=$(echo -e "${line}" | sed -e 's:.*/CN=::')
      CERTS["${i}"]="${NAME}"
      ((i++))
    fi
  done < "${INDEX}"

  for ((ii = 0; ii < ${#CERTS_TO_REVOKE[@]}; ii++)); do
    VALID=0

    for ((x = 1; x <= i; ++x)); do
      if [[ "${CERTS[$x]}" == "${CERTS_TO_REVOKE[ii]}" ]]; then
        VALID=1
      fi
    done

    if [[ "${VALID}" != 1 ]]; then
      err "¡Pasaste un nombre de certificado inválido: '${CERTS_TO_REVOKE[ii]}'!"
      exit 1
    fi
  done
fi

cd /etc/openvpn/easy-rsa || exit

for ((ii = 0; ii < ${#CERTS_TO_REVOKE[@]}; ii++)); do
  if [[ -n "${CONFIRM}" ]]; then
    REPLY="y"
  else
    read -r -p "¿Realmente quieres revocar '${CERTS_TO_REVOKE[ii]}'? [y/N] "
  fi

  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    printf "\n::: Revocando certificado '%s'. \n" "${CERTS_TO_REVOKE[ii]}"

    ./easyrsa --batch revoke "${CERTS_TO_REVOKE[ii]}"
    ./easyrsa gen-crl

    printf "\n::: Certificado revocado y archivo CRL actualizado.\n"
    printf "::: Eliminando certificados y configuración de cliente para este perfil.\n"

    rm -rf "pki/reqs/${CERTS_TO_REVOKE[ii]}.req"
    rm -rf "pki/private/${CERTS_TO_REVOKE[ii]}.key"
    rm -rf "pki/issued/${CERTS_TO_REVOKE[ii]}.crt"

    # Deshabilitando SC2154 $pivpnNET obtenido externamente
    # shellcheck disable=SC2154
    # Obtener la dirección IP del cliente
    STATIC_IP="$(grep -v "^#" /etc/openvpn/ccd/"${CERTS_TO_REVOKE[ii]}" \
      | grep -w ifconfig-push | awk '{print $2}')"
    rm -rf /etc/openvpn/ccd/"${CERTS_TO_REVOKE[ii]}"

    # deshabilitando advertencia SC2154, $install_home obtenido externamente
    # shellcheck disable=SC2154
    rm -rf "${install_home}/ovpns/${CERTS_TO_REVOKE[ii]}.ovpn"
    rm -rf "/etc/openvpn/easy-rsa/pki/${CERTS_TO_REVOKE[ii]}.ovpn"
    cp -a /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem

    if [[ "${TWO_POINT_FIVE}" -eq 1 ]]; then
      # Eliminar metadatos del cliente para bloquear la autenticación a nivel de tls-crypt
      sed '/^'"${CERTS_TO_REVOKE[ii]}"' /d' -i "${TC_V2_METADATA}"
      rm -f "/etc/openvpn/easy-rsa/pki/tc-v2/${CERTS_TO_REVOKE[ii]}.key"
    fi

    # Si se usa Pi-hole, eliminar al cliente del archivo hosts
    if [[ -f /etc/pivpn/hosts.openvpn ]]; then
      sed \
        -e "\#${STATIC_IP} ${CERTS_TO_REVOKE[ii]}.pivpn#d" \
        -i /etc/pivpn/hosts.openvpn

      if killall -SIGHUP pihole-FTL; then
        echo "::: Archivo hosts actualizado para Pi-hole"
      else
        err "::: Falló al recargar la configuración de pihole-FTL"
      fi
    fi
  fi
done

printf "::: ¡Completado!\n"
