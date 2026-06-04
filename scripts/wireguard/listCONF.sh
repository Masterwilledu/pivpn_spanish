#!/bin/bash
### Constantes

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

### Script
cd /etc/wireguard/configs || exit

if [[ ! -s clients.txt ]]; then
  err "::: No hay clientes para listar"
  exit 1
fi

printf "\e[1m::: Resumen de Clientes :::\e[0m\n"

# Muestra al usuario un resumen de los clientes, obteniendo la información de las fechas.
{
  echo -ne "\e[4mCliente\e[0m  \t  \e[4mClave pública\e[0m  \t  "
  echo -e "\e[4mFecha de creación\e[0m"

  while read -r LINE; do
    CLIENT_NAME="$(awk '{print $1}' <<< "${LINE}")"
    PUBLIC_KEY="$(awk '{print $2}' <<< "${LINE}")"
    CREATION_DATE="$(awk '{print $3}' <<< "${LINE}")"
    # Las fechas se convierten de tiempo UNIX a formato legible para humanos.
    CD_FORMAT="$(date -d @"${CREATION_DATE}" +'%d %b %Y, %H:%M, %Z')"
    echo -e "${CLIENT_NAME}  \t  ${PUBLIC_KEY}  \t  ${CD_FORMAT}"
  done < clients.txt
} | column -t -s $'\t'

cd /etc/wireguard || return

echo "::: Clientes deshabilitados :::"
grep '\[disabled\] ### begin' wg0.conf | sed 's/#//g; s/begin//'
