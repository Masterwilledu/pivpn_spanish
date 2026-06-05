#!/bin/bash

### Constantes
setupVars="/etc/pivpn/wireguard/setupVars.conf"

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
  echo "::: Eliminar un perfil de configuración de cliente"
  echo ":::"
  echo -n "::: Uso: pivpn <-r|remove> [-y|--yes] [-h|--help] "
  echo "[<cliente-1> ... [<cliente-2>] ...]"
  echo ":::"
  echo "::: Comandos:"
  echo ":::  [ninguno]            Modo interactivo"
  echo ":::  <cliente>            Cliente(s) a eliminar"
  echo ":::  -y,--yes             Eliminar cliente(s) sin confirmación"
  echo ":::  -h,--help            Mostrar este diálogo de ayuda"
}

### Script
if [[ ! -f "${setupVars}" ]]; then
  err "::: ¡Falta el archivo de variables de configuración!"
  exit 1
fi

# Analizar los argumentos de entrada
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
      CLIENTS_TO_REMOVE+=("${1}")
      ;;
  esac

  shift
done

cd /etc/wireguard || exit

if [[ ! -s configs/clients.txt ]]; then
  err "::: No hay clientes para eliminar"
  exit 1
fi

mapfile -t LIST < <(awk '{print $1}' configs/clients.txt)

if [[ "${#CLIENTS_TO_REMOVE[@]}" -eq 0 ]]; then
  echo -e "::\e[4m  Lista de clientes  \e[0m::"
  len="${#LIST[@]}"
  COUNTER=1

  while [[ "${COUNTER}" -le "${len}" ]]; do
    printf "%0${#len}s) %s\r\n" "${COUNTER}" "${LIST[(($COUNTER - 1))]}"
    ((COUNTER++))
  done

  echo -n "Por favor, introduce el índice/nombre del cliente que deseas eliminar "
  echo -n "de la lista anterior: "
  read -r CLIENTS_TO_REMOVE

  if [[ -z "${CLIENTS_TO_REMOVE}" ]]; then
    err "::: ¡No puedes dejar esto en blanco!"
    exit 1
  fi
fi

DELETED_COUNT=0

for CLIENT_NAME in "${CLIENTS_TO_REMOVE[@]}"; do
  re='^[0-9]+$'

  if [[ "${CLIENT_NAME}" =~ $re ]]; then
    CLIENT_NAME="${LIST[$((CLIENT_NAME - 1))]}"
  fi

  if ! grep -q "^${CLIENT_NAME} " configs/clients.txt; then
    echo -e "::: \e[1m${CLIENT_NAME}\e[0m no existe"
  else
    REQUESTED="$(sha256sum "configs/${CLIENT_NAME}.conf" | cut -c 1-64)"

    if [[ -n "${CONFIRM}" ]]; then
      REPLY="y"
    else
      # Se mantiene el indicador [y/N] para que el usuario sepa que la condición interna espera 'y' o 'Y'
      read -r -p "¿Realmente deseas eliminar a ${CLIENT_NAME}? [y/N] "
    fi

    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
      # Obtener la representación decimal de la dirección IP del cliente
      IPV4_DEC="$(grep "^${CLIENT_NAME} " configs/clients.txt | awk '{print $4}')"
      # La fecha de creación del cliente
      CREATION_DATE="$(grep "^${CLIENT_NAME} " configs/clients.txt \
        | awk '{print $3}')"
      # Y su clave pública
      PUBLIC_KEY="$(grep "^${CLIENT_NAME} " configs/clients.txt \
        | awk '{print $2}')"

      # Luego eliminar el cliente que coincida con las variables de arriba
      sed \
        -e "\#${CLIENT_NAME} ${PUBLIC_KEY} ${CREATION_DATE} ${IPV4_DEC}#d" \
        -i configs/clients.txt

      # Eliminar la sección del peer de la configuración del servidor
      sed_pattern="/### begin ${CLIENT_NAME} ###/,"
      sed_pattern="${sed_pattern}/### end ${CLIENT_NAME} ###/d"
      sed -e "${sed_pattern}" -i wg0.conf
      echo "::: Configuración del servidor actualizada"

      rm "configs/${CLIENT_NAME}.conf"
      echo "::: Configuración de cliente para ${CLIENT_NAME} eliminada"

      rm "keys/${CLIENT_NAME}_priv"
      rm "keys/${CLIENT_NAME}_pub"
      rm "keys/${CLIENT_NAME}_psk"
      echo "::: Claves de cliente para ${CLIENT_NAME} eliminadas"

      # Buscar todos los archivos .conf en la carpeta personal del usuario que coincidan
      # con la suma de verificación (checksum) de la configuración y eliminarlos.
      # Se usa '-maxdepth 3' para
      # evitar recorrer demasiadas carpetas.
      # Deshabilitando SC2154, la variable se origina externamente y puede variar
      # shellcheck disable=SC2154
      while IFS= read -r -d '' CONFIG; do
        if sha256sum -c <<< "${REQUESTED}  ${CONFIG}" &> /dev/null; then
          rm "${CONFIG}"
        fi
      done < <(find "${install_home}" \
        -maxdepth 3 -type f -name '*.conf' -print0)

      ((DELETED_COUNT++))
      echo "::: ${CLIENT_NAME} eliminado con éxito"

      # Si se usa Pi-hole, eliminar el cliente del archivo hosts
      # Deshabilitando SC2154, la variable se origina externamente y puede variar
      # shellcheck disable=SC2154
      if [[ -f /etc/pivpn/hosts.wireguard ]]; then
        IPV4_DOT="$(decIPv4ToDot "${IPV4_DEC}")"
        IPV4_HEX="$(decIPv4ToHex "${IPV4_DEC}")"
        sed \
          -e "\#${IPV4_DOT} ${CLIENT_NAME}.pivpn#d" \
          -e "\#${pivpnNETv6}${IPV4_HEX} ${CLIENT_NAME}.pivpn#d" \
          -i /etc/pivpn/hosts.wireguard

        if killall -SIGHUP pihole-FTL; then
          echo "::: Archivo hosts actualizado para Pi-hole"
        else
          err "::: Fallo al recargar la configuración de pihole-FTL"
        fi
      fi

      unset sed_pattern
    else
      err "Abortando la operación"
      exit 1
    fi
  fi
done

# Reiniciar WireGuard solo si realmente se eliminaron algunos clientes
if [[ "${DELETED_COUNT}" -gt 0 ]]; then
  if [[ "${PLAT}" == 'Alpine' ]]; then
    if rc-service wg-quick restart; then
      echo "::: WireGuard recargado"
    else
      err "::: Fallo al recargar WireGuard"
    fi
  else
    if systemctl reload wg-quick@wg0; then
      echo "::: WireGuard recargado"
    else
      err "::: Fallo al recargar WireGuard"
    fi
  fi
fi
}
