#!/bin/bash

### Constantes
PLAT="$(grep -sEe '^NAME\=' /etc/os-release \
  | sed -E -e "s/NAME\=[\'\"]?([^ ]*).*/\1/")"

# protocolo dual, tipo de VPN suministrado como $1
VPN="${1}"
setupVars="/etc/pivpn/${VPN}/setupVars.conf"
ERR=0

### Funciones
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

### Script
if [[ ! -f "${setupVars}" ]]; then
  err "::: ¡Falta el archivo de variables de configuración!"
  exit 1
fi

# SC1090 deshabilitado ya que el archivo setupVars difiere de un sistema a otro
# shellcheck disable=SC1090
source "${setupVars}"

if [[ "${VPN}" == "wireguard" ]]; then
  VPN_PRETTY_NAME="WireGuard"
  VPN_SERVICE="wg-quick@wg0"

  if [[ "${PLAT}" == 'Alpine' ]]; then
    VPN_SERVICE='wg-quick'
  fi
elif [[ "${VPN}" == "openvpn" ]]; then
  VPN_SERVICE="openvpn"
  VPN_PRETTY_NAME="OpenVPN"
fi

if [[ "$(< /proc/sys/net/ipv4/ip_forward)" -eq 1 ]]; then
  echo ":: [OK] El reenvío IP está habilitado"
else
  ERR=1
  read -r \
    -p ":: [ERR] El reenvío IP no está habilitado, ¿intentar solucionar ahora? [Y/n] " \
    REPLY

  if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
    sed -i '/net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.d/99-pivpn.conf
    sysctl -p
    echo "Hecho"
  fi
fi

if [[ "${USING_UFW}" -eq 0 ]]; then
  # Advertencias SC deshabilitadas para SC2154, los valores
  # para las variables se obtienen de setupVars
  # shellcheck disable=SC2154
  if iptables \
    -t nat \
    -C POSTROUTING \
    -s "${pivpnNET}/${subnetClass}" \
    -o "${IPv4dev}" \
    -j MASQUERADE \
    -m comment \
    --comment "${VPN}-nat-rule" &> /dev/null; then
    echo ":: [OK] Regla MASQUERADE de Iptables establecida"
  else
    ERR=1
    echo -n ":: [ERR] La regla MASQUERADE de Iptables no está establecida, "
    echo -n "¿intentar solucionar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      iptables \
        -t nat \
        -I POSTROUTING \
        -s "${pivpnNET}/${subnetClass}" \
        -o "${IPv4dev}" \
        -j MASQUERADE \
        -m comment \
        --comment "${VPN}-nat-rule"

      iptables-save > /etc/iptables/rules.v4
      echo "Hecho"
    fi
  fi

  if [[ "${INPUT_CHAIN_EDITED}" -eq 1 ]]; then
    # Advertencias SC deshabilitadas para SC2154, los valores
    # para las variables se obtienen de setupVars
    # shellcheck disable=SC2154
    if iptables \
      -C INPUT \
      -i "${IPv4dev}" \
      -p "${pivpnPROTO}" \
      --dport "${pivpnPORT}" \
      -j ACCEPT \
      -m comment \
      --comment "${VPN}-input-rule" &> /dev/null; then
      echo ":: [OK] Regla INPUT de Iptables establecida"
    else
      ERR=1
      read -r \
        -p ":: [ERR] La regla INPUT de Iptables no está establecida, ¿intentar solucionar ahora? [Y/n] " \
        REPLY

      if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
        iptables \
          -I INPUT 1 \
          -i "${IPv4dev}" \
          -p "${pivpnPROTO}" \
          --dport "${pivpnPORT}" \
          -j ACCEPT \
          -m comment \
          --comment "${VPN}-input-rule"

        iptables-save > /etc/iptables/rules.v4
        echo "Hecho"
      fi
    fi
  fi

  if [[ "${FORWARD_CHAIN_EDITED}" -eq 1 ]]; then
    # Advertencias SC deshabilitadas para SC2154, los valores
    # para las variables se obtienen de setupVars
    # shellcheck disable=SC2154
    if iptables \
      -C FORWARD \
      -s "${pivpnNET}/${subnetClass}" \
      -i "${pivpnDEV}" \
      -o "${IPv4dev}" \
      -j ACCEPT \
      -m comment \
      --comment "${VPN}-forward-rule" &> /dev/null; then
      echo ":: [OK] Regla FORWARD de Iptables establecida"
    else
      ERR=1
      echo -n ":: [ERR] La regla FORWARD de Iptables no está establecida, "
      echo -n "¿intentar solucionar ahora? [Y/n] "
      read -r REPLY

      if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
        iptables \
          -I FORWARD 1 \
          -d "${pivpnNET}/${subnetClass}" \
          -i "${IPv4dev}" \
          -o "${pivpnDEV}" \
          -m conntrack \
          --ctstate RELATED,ESTABLISHED \
          -j ACCEPT \
          -m comment \
          --comment "${VPN}-forward-rule"

        iptables \
          -I FORWARD 2 \
          -s "${pivpnNET}/${subnetClass}" \
          -i "${pivpnDEV}" \
          -o "${IPv4dev}" \
          -j ACCEPT \
          -m comment \
          --comment "${VPN}-forward-rule"

        iptables-save > /etc/iptables/rules.v4
        echo "Hecho"
      fi
    fi
  fi
else
  if LANG="en_US.UTF-8" ufw status | grep -qw 'active'; then
    echo ":: [OK] Ufw está habilitado"
  else
    ERR=1
    echo -n ":: [ERR] Ufw no está habilitado, "
    echo -n "¿intentar habilitar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      ufw enable
    fi
  fi

  if iptables \
    -t nat \
    -C POSTROUTING \
    -s "${pivpnNET}/${subnetClass}" \
    -o "${IPv4dev}" \
    -j MASQUERADE \
    -m comment \
    --comment "${VPN}-nat-rule" &> /dev/null; then
    echo ":: [OK] Regla MASQUERADE de Iptables establecida"
  else
    ERR=1
    echo -n ":: [ERR] La regla MASQUERADE de Iptables no está establecida, "
    echo -n "¿intentar solucionar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      sed_pattern='/delete these required/i'
      sed_pattern="${sed_pattern} *nat\n:POSTROUTING ACCEPT [0:0]\n"
      sed_pattern="${sed_pattern} -I POSTROUTING"
      sed_pattern="${sed_pattern} -s ${pivpnNET}/${subnetClass}"
      sed_pattern="${sed_pattern} -o ${IPv4dev}"
      sed_pattern="${sed_pattern} -j MASQUERADE"
      sed_pattern="${sed_pattern} -m comment"
      sed_pattern="${sed_pattern} --comment ${VPN}-nat-rule\n"
      sed_pattern="${sed_pattern}COMMIT\n"

      sed "${sed_pattern}" -i /etc/ufw/before.rules
      ufw reload
      echo "Hecho"
      unset sed_pattern
    fi
  fi

  if iptables \
    -C ufw-user-input \
    -p "${pivpnPROTO}" \
    --dport "${pivpnPORT}" \
    -j ACCEPT &> /dev/null; then
    echo ":: [OK] Regla de entrada Ufw establecida"
  else
    ERR=1
    read -r \
      -p ":: [ERR] La regla de entrada Ufw no está establecida, ¿intentar solucionar ahora? [Y/n] " \
      REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      ufw insert 1 allow "${pivpnPORT}"/"${pivpnPROTO}"
      ufw reload
      echo "Hecho"
    fi
  fi

  if iptables \
    -C ufw-user-forward \
    -i "${pivpnDEV}" \
    -o "${IPv4dev}" \
    -s "${pivpnNET}/${subnetClass}" \
    -j ACCEPT &> /dev/null; then
    echo ":: [OK] Regla de reenvío Ufw establecida"
  else
    ERR=1
    read -r \
      -p ":: [ERR] La regla de reenvío Ufw no está establecida, ¿intentar solucionar ahora? [Y/n] " \
      REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      ufw route insert 1 allow in on "${pivpnDEV}" \
        from "${pivpnNET}/${subnetClass}" out on "${IPv4dev}" to any
      ufw reload
      echo "Hecho"
    fi
  fi
fi

if [[ "${PLAT}" == 'Alpine' ]]; then
  if [[ "$(rc-service "${VPN_SERVICE}" status \
    | sed -E -e 's/.*status\: (.*)/\1/')" == 'started' ]]; then
    echo ":: [OK] ${VPN_PRETTY_NAME} se está ejecutando"
  else
    ERR=1
    echo -n ":: [ERR] ${VPN_PRETTY_NAME} no se está ejecutando, "
    echo -n "¿intentar iniciar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      rc-service -s "${VPN_SERVICE}" restart
      rc-service -N "${VPN_SERVICE}" start
      echo "Hecho"
    fi
  fi

  if rc-update show default \
    | grep -sEe "\s*${VPN_SERVICE} .*" &> /dev/null; then
    echo -n ":: [OK] ${VPN_PRETTY_NAME} está habilitado "
    echo "(se iniciará automáticamente al reiniciar)"
  else
    ERR=1
    echo -n ":: [ERR] ${VPN_PRETTY_NAME} no está habilitado, "
    echo -n "¿intentar habilitar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      rc-update add "${VPN_SERVICE}" default
      echo "Hecho"
    fi
  fi
else
  if systemctl is-active -q "${VPN_SERVICE}"; then
    echo ":: [OK] ${VPN_PRETTY_NAME} se está ejecutando"
  else
    ERR=1
    echo -n ":: [ERR] ${VPN_PRETTY_NAME} no se está ejecutando, "
    echo -n "¿intentar iniciar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      systemctl start "${VPN_SERVICE}"
      echo "Hecho"
    fi
  fi

  if systemctl is-enabled -q "${VPN_SERVICE}"; then
    echo ":: [OK] ${VPN_PRETTY_NAME} está habilitado "
    echo "(se iniciará automáticamente al reiniciar)"
  else
    ERR=1
    echo -n ":: [ERR] ${VPN_PRETTY_NAME} no está habilitado, "
    echo -n "¿intentar habilitar ahora? [Y/n] "
    read -r REPLY

    if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
      systemctl enable "${VPN_SERVICE}"
      echo "Hecho"
    fi
  fi
fi

# Se usa grep -w (palabra completa) para que el puerto 11940 no coincida al buscar 1194
if netstat -antu | grep -wqE "${pivpnPROTO}.*${pivpnPORT}"; then
  echo -n ":: [OK] ${VPN_PRETTY_NAME} está escuchando "
  echo "en el puerto ${pivpnPORT}/${pivpnPROTO}"
else
  ERR=1
  echo -n ":: [ERR] ${VPN_PRETTY_NAME} no está escuchando, "
  echo -n "¿intentar reiniciar ahora? [Y/n] "
  read -r REPLY

  if [[ "${REPLY}" =~ ^[Yy]$ ]] || [[ -z "${REPLY}" ]]; then
    if [[ "${PLAT}" == 'Alpine' ]]; then
      rc-service -s "${VPN_SERVICE}" restart
      rc-service -N "${VPN_SERVICE}" start
    else
      systemctl restart "${VPN_SERVICE}"
    fi

    echo "Hecho"
  fi
fi

if [[ "${ERR}" -eq 1 ]]; then
  echo -e "[INFO] Ejecuta \e[1mpivpn -d\e[0m de nuevo para ver si detectamos problemas"
fi
