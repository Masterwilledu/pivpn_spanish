#!/usr/bin/env bash
# PiVPN: Script de Actualización de Componentes y Lógica Interna
# Sincroniza los entornos de ejecución locales con las ramas de desarrollo de GitHub.

export LANG=es_ES.UTF-8
export LC_ALL=es_ES.UTF-8

# ==============================================================================
# CONTROL DE DESACTIVACIÓN TEMPORAL (CONMUTADOR DE FUNCIONALIDAD)
# ==============================================================================
# Cambiar a 'false' para activar por completo la ejecución del actualizador.
DISABLE_UPDATE=true

err() {
  echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ::: [ERROR] $*" >&2
}

if [[ "${DISABLE_UPDATE}" == "true" ]]; then
  err "La funcionalidad nativa de actualización automatizada está temporalmente deshabilitada."
  err "Para mantener el sistema operativo y sus dependencias al día, ejecute manualmente:"
  echo -e "    \e[1msudo apt update && sudo apt upgrade\e[0m"
  exit 0
fi
# ==============================================================================

# Privilegios de administrador requeridos para operaciones en /opt y /etc
if [[ "${EUID}" -ne 0 ]]; then
  err "Este script requiere privilegios de acceso raíz (root). Intente usar 'sudo'."
  exit 1
fi

# Validación preventiva del binario Git en el sistema anfitrión
if ! command -v git &> /dev/null; then
  err "El binario 'git' es indispensable y no está disponible en el PATH del sistema."
  exit 1
fi

# ==============================================================================
#                 CONFIGURACIÓN DE GEOMETRÍA Y CONSTANTES GLOBALES
# ==============================================================================
pivpnrepo="https://github.com/wfhgdev/pivpn_spanish.git"
pivpnlocalpath="/etc/.pivpn"
pivpnscripts="/opt/pivpn"
bashcompletiondir="/etc/bash_completion.d"

screen_size="$(stty size 2> /dev/null || echo 24 80)"
rows="$(echo "${screen_size}" | awk '{print $1}')"
columns="$(echo "${screen_size}" | awk '{print $2}')"

# Proporciones dinámicas para ventanas TUI (Whiptail)
r=$((rows / 2))
c=$((columns / 2))
r=$((r < 20 ? 20 : r))
c=$((c < 70 ? 70 : c))

# Asistente gráfico interactivo de selección de protocolo
chooseVPNCmd=(whiptail
  --backtitle "Ecosistema de Gestión PiVPN"
  --title "Actualización de Componentes"
  --ok-button "Seleccionar"
  --cancel-button "Salir"
  --separate-output
  --radiolist "Seleccione el protocolo VPN cuyos scripts desea sincronizar:\n(Presione [Espacio] para marcar, [Intro] para continuar)"
  "${r}" "${c}" 2)

VPNChooseOptions=(WireGuard "Actualizar scripts del entorno WireGuard" on
                  OpenVPN "Actualizar scripts del entorno OpenVPN" off)

if VPN="$("${chooseVPNCmd[@]}" "${VPNChooseOptions[@]}" 2>&1 > /dev/tty)"; then
  VPN="${VPN,,}"
  echo "::: [INFO] Instancia seleccionada para auditoría: ${VPN}"
else
  echo "::: [INFO] Operación cancelada por el usuario. Saliendo..."
  exit 0
fi

setupVars="/etc/pivpn/${VPN}/setupVars.conf"

# Validación estructural del archivo de configuración antes de su invocación (source)
if [[ ! -f "${setupVars}" ]]; then
  err "No se localizó el archivo de configuración indispensable en: ${setupVars}"
  exit 1
fi

# shellcheck disable=SC1090
source "${setupVars}"

# ==============================================================================
#                            LOGICA DE FUNCIONES
# ==============================================================================

scriptusage() {
  echo "::: [INFO] Manual de Uso - Módulo de Actualización PiVPN"
  echo ":::"
  echo "::: Comando: pivpn <-up|update> [Opciones]"
  echo ":::"
  echo "::: Opciones válidas:"
  echo ":::   [Ninguna]       Sincroniza el entorno desde la rama estable 'master'."
  echo ":::   -t, test        Sincroniza el entorno desde la rama de desarrollo 'test'."
  echo ":::   -h, help        Despliega este manual de ayuda en la consola."
}

cloneandupdate() {
  local branch="${1:-master}"

  echo "::: [INFO] Sincronizando repositorio remoto con la caché local..."
  if ! git clone "${pivpnrepo}" "${pivpnlocalpath}" &> /dev/null; then
    err "Fallo crítico al intentar clonar el repositorio: ${pivpnrepo}"
    exit 1
  fi

  # Cambiar de rama únicamente si difiere de la rama master por defecto
  if [[ "${branch}" != "master" ]]; then
    echo "::: [INFO] Cambiando el espacio de trabajo local a la rama de desarrollo: '${branch}'..."
    if ! git -C "${pivpnlocalpath}" checkout "${branch}" &> /dev/null; then
      err "La rama especificada '${branch}' no está disponible en el servidor remoto."
      rm -rf "${pivpnlocalpath}"
      exit 1
    fi
    git -C "${pivpnlocalpath}" pull origin "${branch}" &> /dev/null
  fi

  echo "::: [INFO] Desplegando nuevos ejecutables en los directorios del sistema..."
  mkdir -p "${pivpnscripts}" "${bashcompletiondir}"

  # Copia segura protegiendo comodines en caso de directorios vacíos
  cp "${pivpnlocalpath}"/scripts/*.sh "${pivpnscripts}/" 2>/dev/null || true
  cp "${pivpnlocalpath}"/scripts/${VPN}/*.sh "${pivpnscripts}/" 2>/dev/null || true
  cp "${pivpnlocalpath}"/scripts/${VPN}/bash-completion "${bashcompletiondir}/pivpn" 2>/dev/null || true

  # Dejar el repositorio local limpio apuntando a master si se trabajó en otra rama
  if [[ "${branch}" != "master" ]]; then
    git -C "${pivpnlocalpath}" checkout master &> /dev/null
  fi
}

updatepivpnscripts() {
  local target_branch="${1:-master}"
  echo "::: [INFO] Iniciando secuencia de actualización desde la rama: '${target_branch}'"

  # Salvaguarda estructural para mitigar riesgos de borrado accidental catastrófico
  if [[ -d "${pivpnlocalpath}" ]]; then
    if [[ "${pivpnlocalpath}" != "/" && "${pivpnlocalpath}" != "/etc" ]]; then
      echo "::: [INFO] Limpiando espacio temporal previo en ${pivpnlocalpath}..."
      rm -rf "${pivpnlocalpath}"
    fi
  fi

  cloneandupdate "${target_branch}"
  echo "::: [ÉXITO] Todos los scripts se han actualizado correctamente desde la rama '${target_branch}'."
}

# ==============================================================================
#                      PROCESAMIENTO DE ARGUMENTOS CLI
# ==============================================================================

case "${1}" in
  -t | test)
    updatepivpnscripts "test"
    ;;
  -h | help)
    scriptusage
    ;;
  "")
    updatepivpnscripts "master"
    ;;
  *)
    echo "::: [ADVERTENCIA] Opción no reconocida: '${1}'."
    scriptusage
    exit 1
    ;;
esac

exit 0