#!/bin/bash
# PiVPN: script de estado de clientes

### Constantes
CLIENTS_FILE="/etc/wireguard/configs/clients.txt"

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

scriptusage() {
  echo "::: Lista cualquier cliente conectado al servidor"
  echo ":::"
  echo "::: Uso: pivpn <-c|clients> [-b|bytes]"
  echo ":::"
  echo "::: Comandos:"
  echo ":::  [ninguno]           Lista clientes con formato legible para humanos"
  echo ":::  -b, bytes           Lista clientes con notación decimal"
  echo ":::  -h, help            Muestra este diálogo de uso"
}

hr() {
  numfmt --to=iec-i --suffix=B "${1}"
}

listClients() {
  if DUMP="$(wg show wg0 dump)"; then
    DUMP="$(tail -n +2 <<< "${DUMP}")"
  else
    exit 1
  fi

  printf "\e[1m::: Lista de Clientes Conectados :::\e[0m\n"

  {
    printf "\e[4mNombre\e[0m  \t  \e[4mIP Remota\e[0m  \t  \e[4mIP Virtual\e[0m"
    printf "\t  \e[4mBytes Recibidos\e[0m  \t  \e[4mBytes Enviados\e[0m  "
    printf "\t  \e[4mÚltima Conexión\e[0m\n"

    while IFS= read -r LINE; do
      if [[ -n "${LINE}" ]]; then
        PUBLIC_KEY="$(awk '{ print $1 }' <<< "${LINE}")"
        REMOTE_IP="$(awk '{ print $3 }' <<< "${LINE}")"
        VIRTUAL_IP="$(awk '{ print $4 }' <<< "${LINE}")"
        BYTES_RECEIVED="$(awk '{ print $6 }' <<< "${LINE}")"
        BYTES_SENT="$(awk '{ print $7 }' <<< "${LINE}")"
        LAST_SEEN="$(awk '{ print $5 }' <<< "${LINE}")"
        CLIENT_NAME="$(grep "${PUBLIC_KEY}" "${CLIENTS_FILE}" \
          | awk '{ print $1 }')"
        printf "%s  \t  %s  \t  %s  \t  " \
          "${CLIENT_NAME}" \
          "${REMOTE_IP}" \
          "${VIRTUAL_IP/\/32/}"

        if [[ "${HR}" == 1 ]]; then
          printf "%s  \t  %s  \t  " \
            "$(hr "${BYTES_RECEIVED}")" \
            "$(hr "${BYTES_SENT}")"
        else
          printf "%s  \t  %s  \t  " "${BYTES_RECEIVED}" "${BYTES_SENT}"
        fi

        if [[ "${LAST_SEEN}" -ne 0 ]]; then
          printf "%s" "$(date -d @"${LAST_SEEN}" '+%b %d %Y - %T')"
        else
          printf "(aún no)"
        fi

        printf "\n"
      fi
    done <<< "${DUMP}"

    printf "\n"
  } | column -ts $'\t'

  cd /etc/wireguard || return

  echo "::: Clientes deshabilitados :::"
  grep '\[disabled\] ### begin' wg0.conf | sed 's/#//g; s/begin//'
}

### Script
if [[ ! -s "${CLIENTS_FILE}" ]]; then
  err "::: No hay clientes para listar"
  exit 0
fi

if [[ "$#" -eq 0 ]]; then
  HR=1
  listClients
else
  while true; do
    case "${1}" in
      -b | bytes)
        HR=0
        listClients
        exit 0
        ;;
      -h | help)
        scriptusage
        exit 0
        ;;
      *)
        HR=0
        listClients
        exit 0
        ;;
    esac
  done
fi
