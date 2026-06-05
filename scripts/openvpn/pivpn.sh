#!/bin/bash

### Constantes
CHECK_PKG_INSTALLED='dpkg-query -s'

if grep -qsEe "^NAME\=['\"]?Alpine[a-zA-Z ]*['\"]?$" /etc/os-release; then
  CHECK_PKG_INSTALLED='apk --no-cache info -e'
fi

scriptDir="/opt/pivpn"
vpn="openvpn"

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

makeOVPNFunc() {
  shift
  ${SUDO} "${scriptDir}/${vpn}/makeOVPN.sh" "$@"
  exit "${?}"
}

listClientsFunc() {
  shift
  ${SUDO} "${scriptDir}/${vpn}/clientStat.sh" "$@"
  exit "${?}"
}

listOVPNFunc() {
  ${SUDO} "${scriptDir}/${vpn}/listOVPN.sh"
  exit "${?}"
}

debugFunc() {
  echo "::: Generando salida de depuración"

  ${SUDO} "${scriptDir}/${vpn}/pivpnDebug.sh" | tee /tmp/debug.log
  e="${?}"

  echo "::: "
  echo "::: Salida de depuración completada arriba."
  echo "::: Copia guardada en /tmp/debug.log"
  echo "::: "
  exit "${e}"
}

removeOVPNFunc() {
  shift
  ${SUDO} "${scriptDir}/${vpn}/removeOVPN.sh" "$@"
  exit "${?}"
}

uninstallFunc() {
  ${SUDO} "${scriptDir}/uninstall.sh" "${vpn}"
  exit "${?}"
}

update() {
  shift
  ${SUDO} "${scriptDir}/update.sh" "$@"
  exit "${?}"
}

backup() {
  ${SUDO} "${scriptDir}/backup.sh" "${vpn}"
  exit "${?}"
}

helpFunc() {
  echo "::: ¡Controla todas las funciones específicas de PiVPN!"
  echo ":::"
  echo "::: Uso: pivpn <comando> [opción]"
  echo ":::"
  echo "::: Comandos:"
  echo ":::  -a, add [nopass]     Crear un perfil ovpn de cliente, nopass opcional"
  echo ":::  -c, clients          Listar los clientes conectados al servidor"
  echo ":::  -d, debug            Iniciar una sesión de depuración si tienes problemas"
  echo ":::  -l, list             Listar todos los certificados válidos y revocados"
  echo ":::  -r, revoke           Revocar un perfil ovpn de cliente"
  echo ":::  -h, help             Mostrar este diálogo de ayuda"
  echo ":::  -u, uninstall        ¡Desinstalar PiVPN de tu sistema!"
  echo ":::  -up, update          Actualizar los scripts de PiVPN"
  echo ":::  -bk, backup          Respaldar el directorio de Openvpn y ovpns"
  exit 0
}

# Debe ser root para usar esta herramienta
if [[ "${EUID}" -ne 0 ]]; then
  if ${CHECK_PKG_INSTALLED} sudo &> /dev/null; then
    export SUDO="sudo"
  else
    err "::: Por favor, instala sudo o ejecuta esto como root."
    exit 1
  fi
fi

if [[ "$#" == 0 ]]; then
  helpFunc
fi

# Manejar la redirección a funciones específicas según los argumentos
case "${1}" in
  "-a" | "add")
    makeOVPNFunc "$@"
    ;;
  "-c" | "clients")
    listClientsFunc "$@"
    ;;
  "-d" | "debug")
    debugFunc
    ;;
  "-l" | "list")
    listOVPNFunc
    ;;
  "-r" | "revoke")
    removeOVPNFunc "$@"
    ;;
  "-h" | "help")
    helpFunc
    ;;
  "-u" | "uninstall")
    uninstallFunc
    ;;
  "-up" | "update")
    update "$@"
    ;;
  "-bk" | "backup")
    backup
    ;;
  *)
    helpFunc
    ;;
esac
