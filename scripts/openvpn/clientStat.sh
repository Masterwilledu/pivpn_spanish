#!/bin/bash
# PiVPN: script de estado de clientes

STATUS_LOG="/var/log/openvpn-status.log"

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
  printf ": NOTA: La salida que se muestra a continuación NO es en tiempo real!\n"
  printf ":      : Puede tener un desfase de unos minutos.\n"
  printf "\n"
  printf "\e[1m::: Lista de Estado de Clientes :::\e[0m\n"

  {
    printf "\e[4mNombre\e[0m  \t  \e[4mIP Remota\e[0m  \t  "
    printf "\e[4mIP Virtual\e[0m  \t  \e[4mBytes Recibidos\e[0m  \t  "
    printf "\e[4mBytes Enviados\e[0m  \t  \e[4mConectado Desde\e[0m\n"

    if grep -q "^CLIENT_LIST" "${STATUS_LOG}"; then
      if [[ -n "$(type -t numfmt)" ]]; then
        while read -r line; do
          read -r -a array <<< "${line}"

          [[ "${array[0]}" == 'CLIENT_LIST' ]] || continue

          printf "%s  \t  %s  \t  " "${array[1]}" "${array[2]}"
          printf "%s  \t  " "${array[3]}"

          if [[ "${HR}" == 1 ]]; then
            printf "%s  \t  %s" "$(hr "${array[4]}")" "$(hr "${array[5]}")"
          else
            printf "%'d  \t  %'d" "${array[4]}" "${array[5]}"
          fi

          printf "  \t  %s %s %s " "${array[7]}" "${array[8]}" "${array[10]}"
          printf "%s\n" "${array[9]}"
          printf "\n"
        done < "${STATUS_LOG}"
      else
        awk -F ' ' -v s='CLIENT_LIST' \
          '$1 == s {
            print $2"\t\t"$3"\t"$4"\t"$5"\t\t"$6"\t\t"$8" "$9" "$11" - "$10"\n"
          }' \
          "${STATUS_LOG}"
      fi
    else
      printf "\nNo hay clientes conectados!\n"
    fi

    printf "\n"
  } | column -t -s $'\t'
}

if [[ ! -f "${STATUS_LOG}" ]]; then
  err "¡No se encontró el archivo: ${STATUS_LOG}!"
  exit 1
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
