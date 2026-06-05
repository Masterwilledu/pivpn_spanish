#!/bin/bash

### Constantes

setupVars="/etc/pivpn/wireguard/setupVars.conf"

# shellcheck disable=SC1090
source "${setupVars}"

### Funciones

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

### Script

# Este script se ejecuta como root
if [[ ! -f "${setupVars}" ]]; then
  err "::: ¡Falta el archivo de variables de configuración!"
  exit 1
fi

echo -e "::::\t\t\e[4mDepuración de PiVPN\e[0m\t\t ::::"
printf "=============================================\n"
echo -e "::::\t\t\e[4mÚltimo commit\e[0m\t\t ::::"
echo -n "Rama: "

git --git-dir /usr/local/src/pivpn/.git rev-parse --abbrev-ref HEAD
git \
  --git-dir /usr/local/src/pivpn/.git log -n 1 \
  --format='Commit: %H%nAutor: %an%nFecha: %ad%nResumen: %s'

printf "=============================================\n"
echo -e "::::\t    \e[4mAjustes de instalación\e[0m    \t ::::"

# Deshabilitando la advertencia SC2154, la variable se origina externamente y puede variar
# shellcheck disable=SC2154
sed "s/${pivpnHOST}/REDACTADO/" < "${setupVars}"

printf "=============================================\n"
echo -e "::::  \e[4mConfiguración del servidor a continuación\e[0m   ::::"

cd /etc/wireguard/keys || exit
cp ../wg0.conf ../wg0.tmp

# Reemplazar cada clave en la configuración del servidor solo con su nombre de archivo
for k in *; do
  sed "s#$(< "${k}")#${k}#" -i ../wg0.tmp
done

cat ../wg0.tmp
rm ../wg0.tmp

printf "=============================================\n"
echo -e "::::  \e[4mConfiguración del cliente a continuación\e[0m   ::::"

EXAMPLE="$(head -1 /etc/wireguard/configs/clients.txt | awk '{print $1}')"

if [[ -n "${EXAMPLE}" ]]; then
  cp ../configs/"${EXAMPLE}".conf ../configs/"${EXAMPLE}".tmp

  for k in *; do
    sed "s#$(< "${k}")#${k}#" -i ../configs/"${EXAMPLE}".tmp
  done

  sed "s/${pivpnHOST}/REDACTADO/" < ../configs/"${EXAMPLE}".tmp
  rm ../configs/"${EXAMPLE}".tmp
else
  echo "::: Aún no hay clientes"
fi

printf "=============================================\n"
echo -e ":::: \t\e[4mLista recursiva de archivos en\e[0m\t ::::"
echo -e "::::\t\e[4m/etc/wireguard a continuación\e[0m\t ::::"

ls -LR /etc/wireguard

printf "=============================================\n"
echo -e "::::\t\t\e[4mAutoverificación\e[0m\t\t ::::"

/opt/pivpn/self_check.sh "${VPN}"

printf "=============================================\n"
echo -e ":::: ¿Tienes problemas para conectar? Echa un vistazo a las preguntas frecuentes (FAQ):"
echo -e ":::: \e[1mhttps://docs.pivpn.io/faqe[0m"
printf "=============================================\n"
echo -ne ":::: \e[1mADVERTENCIA\e[0m: Este script debería haber "
echo -e "ocultado automáticamente la información       ::::"
echo -ne ":::: sensible; sin embargo, asegúrate de que "
echo -e "\e[4mPrivateKey\e[0m, \e[4mPublicKey\e[0m      ::::"
echo -ne ":::: y \e[4mPresharedKey\e[0m estén ocultas antes de "
echo -e "informar un problema. Una clave de ejemplo ::::"
echo -n ":::: que NO deberías ver en este registro se ve así:"
echo "                  ::::"
echo -n ":::: YIAoJVsdIeyvXfGGDDadHh6AxsMRymZTnnzZoAb9cxRe"
echo "                          ::::"
printf "=============================================\n"
echo -e "::::\t\t\e[4mDepuración completada\e[0m\t\t ::::"
