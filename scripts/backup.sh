#!/bin/bash
# PiVPN: Script de Copia de Respaldo

### Constantes
# Encuentra las filas y columnas. Por defecto será 80x24 si no se puede detectar.
screen_size="$(stty size 2> /dev/null || echo 24 80)"
rows="$(echo "${screen_size}" | awk '{print $1}')"
columns="$(echo "${screen_size}" | awk '{print $2}')"

# Dividir por dos para que los cuadros de diálogo ocupen la mitad de la pantalla, lo que se ve bien.
r=$((rows / 2))
c=$((columns / 2))
# A menos que la pantalla sea minúscula
r=$((r < 20 ? 20 : r))
c=$((c < 70 ? 70 : c))

backupdir=pivpnbackup
date="$(date +%Y%m%d-%H%M%S)"
setupVarsFile="setupVars.conf"
setupConfigDir="/etc/pivpn"

CHECK_PKG_INSTALLED='dpkg-query -s'

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

checkbackupdir() {
  # Deshabilitando el error de shellcheck, $install_home se obtiene de $setupVars
  # shellcheck disable=SC2154
  mkdir -p "${install_home}/${backupdir}"
}

backup_openvpn() {
  openvpndir=/etc/openvpn
  ovpnsdir="${install_home}/ovpns"
  backupzip="${date}-pivpnovpnbackup.tgz"

  checkbackupdir
  # shellcheck disable=SC2154
  echo "::: Realizando respaldo de OpenVPN..."
  
  # shellcheck disable=SC2154
  tar -czf "${install_home}/${backupdir}/${backupzip}" \
    "${openvpndir}/easy-rsa/pki" \
    "${openvpndir}/server.conf" \
    "${ovpnsdir}" \
    "${setupConfigDir}/openvpn/${setupVarsFile}" 2> /dev/null

  echo "::: Respaldo creado en: ${install_home}/${backupdir}/${backupzip}"
}

backup_wireguard() {
  wgdir=/etc/wireguard
  backupzip="${date}-pivpnwgbackup.tgz"

  checkbackupdir
  echo "::: Realizando respaldo de WireGuard..."

  # shellcheck disable=SC2154
  tar -czf "${install_home}/${backupdir}/${backupzip}" \
    "${wgdir}/wg0.conf" \
    "${wgdir}/keys" \
    "${install_home}/configs" \
    "${setupConfigDir}/wireguard/${setupVarsFile}" 2> /dev/null

  echo "::: Respaldo creado en: ${install_home}/${backupdir}/${backupzip}"
}

### Script
if [[ -r "${setupConfigDir}/wireguard/${setupVarsFile}" ]] \
  && [[ -r "${setupConfigDir}/openvpn/${setupVarsFile}" ]]; then

  # Se han instalado dos protocolos, comprobar si el script ha recibido
  # un argumento, de lo contrario preguntar al usuario cuál quiere respaldar
  if [[ "$#" -ge 1 ]]; then
    VPN="${1}"
    echo "::: Respaldando VPN: ${VPN}"
  else
    chooseVPNCmd=(whiptail
      --backtitle "Configuración de PiVPN"
      --title "Respaldo"
      --separate-output
      --radiolist "Tanto OpenVPN como WireGuard están instalados, elige una VPN para \
respaldar (presiona espacio para seleccionar):"
      "${r}" "${c}" 2)
    VPNChooseOptions=(WireGuard "" on
      OpenVPN "" off)

    if VPN="$("${chooseVPNCmd[@]}" "${VPNChooseOptions[@]}" 2>&1 \
      > /dev/tty)"; then
      echo "::: Respaldando VPN: ${VPN}"
      VPN="${VPN,,}"
    else
      err "::: Selección cancelada, saliendo..."
      exit 1
    fi
  fi

  setupVars="${setupConfigDir}/${VPN}/${setupVarsFile}"
else
  if [[ -r "${setupConfigDir}/wireguard/${setupVarsFile}" ]]; then
    setupVars="${setupConfigDir}/wireguard/${setupVarsFile}"
  elif [[ -r "${setupConfigDir}/openvpn/${setupVarsFile}" ]]; then
    setupVars="${setupConfigDir}/openvpn/${setupVarsFile}"
  fi
fi

if [[ ! -f "${setupVars}" ]]; then
  err "::: ¡Falta el archivo de variables de configuración!"
  exit 1
fi

# shellcheck disable=SC1090
source "${setupVars}"

if [[ "${PLAT}" == 'Alpine' ]]; then
  CHECK_PKG_INSTALLED='apk --no-cache info -e'
fi

if [[ "${VPN}" == "wireguard" ]]; then
  backup_wireguard
elif [[ "${VPN}" == "openvpn" ]]; then
  backup_openvpn
fi
