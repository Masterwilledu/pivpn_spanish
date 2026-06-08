# PiVPN en Español (Fork Comunitario)

Este proyecto es un **fork del repositorio original de PiVPN**. Actualmente, el proyecto oficial [PiVPN](https://pivpn.io) no está recibiendo mantenimiento activo, por lo que este fork surge con el objetivo de preservar su funcionalidad, corregir errores y mejorar la experiencia de usuario para la comunidad hispanohablante.

## 🚀 ¿Qué hace especial a esta versión?

A diferencia de la versión original, este fork ha sido rediseñado para ser más intuitivo, asertivo y amigable para el usuario. Las mejoras principales incluyen:

* **Localización Completa al Español:** Se ha traducido íntegramente la interfaz de línea de comandos (CLI) y todos los diálogos interactivos (`whiptail`). Ya no hay confusiones técnicas por barreras idiomáticas.
* **Redacción Asertiva y UX Mejorada:** Hemos reescrito todos los mensajes del instalador para que sean:
    * **Clarificadores:** Eliminamos tecnicismos innecesarios y explicamos el "porqué" de cada opción.
    * **Amigables:** Se eliminó el tono punitivo o intimidatorio de los mensajes originales, reemplazándolo por una guía constructiva.
    * **Profesionales:** Mejora en la estructuración de la información, el uso de viñetas y el flujo de los botones de acción para facilitar la toma de decisiones.
* **Logs Consistentes:** La salida en consola (`echo`) ha sido estandarizada para ofrecer un log de instalación limpio, legible y profesional.
* **Compatibilidad Actualizada:** Se han corregido diversos scripts de validación para garantizar la compatibilidad con las versiones más recientes de **Debian/Ubuntu** y sus derivados.

## 📋 Requisitos Mínimos

Para ejecutar el instalador sin problemas, asegúrate de contar con:

* Un sistema operativo basado en **Debian** o **Ubuntu** (Raspberry Pi OS, Armbian, Ubuntu Server, etc.).
* Acceso a privilegios de administrador (`sudo`).
* Conexión a internet activa para la descarga de paquetes.
* `curl` instalado en el sistema.

## 🛠 Instalación

Puedes ejecutar el instalador directamente desde tu terminal con el siguiente comando:

```bash
curl -sSfL [https://raw.githubusercontent.com/wfhgdev/pivpn_spanish/master/auto_install/install.sh](https://raw.githubusercontent.com/wfhgdev/pivpn_spanish/master/auto_install/install.sh) | bash