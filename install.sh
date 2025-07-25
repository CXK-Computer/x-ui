#!/bin/bash

# Este script debe ejecutarse con 'bash', no con el 'sh' por defecto de OpenWrt.

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# --- Funciones de Log ---
LOGD() { echo -e "${yellow}[DEG] $* ${plain}"; }
LOGE() { echo -e "${red}[ERR] $* ${plain}"; }
LOGI() { echo -e "${green}[INF] $* ${plain}"; }

# --- Comprobar Root ---
[[ $EUID -ne 0 ]] && LOGE "Error: Debe usar el usuario root para ejecutar este script.\n" && exit 1

# --- Detección de OS y Arquitectura ---
if [[ -f /etc/openwrt_release ]]; then
    release="openwrt"
    LOGI "Sistema OpenWrt detectado."
else
    LOGE "Este script está diseñado exclusivamente para OpenWrt."
    exit 1
fi

arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv8l) arch="arm64" ;;
    *)
        LOGE "Arquitectura no soportada: ${arch}. Este script solo soporta amd64 y arm64."
        LOGI "Las versiones de x-ui solo están disponibles para amd64, arm64 y s390x."
        exit 1
        ;;
esac
LOGI "Arquitectura detectada: ${arch}"


# --- Función para crear el script de gestión /usr/bin/x-ui ---
create_management_script() {
    LOGI "Creando el script de gestión adaptado para OpenWrt en /usr/bin/x-ui..."
    cat > /usr/bin/x-ui << 'EOF'
#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
function LOGD(){ echo -e "${yellow}[DEG] $* ${plain}"; }
function LOGE(){ echo -e "${red}[ERR] $* ${plain}"; }
function LOGI(){ echo -e "${green}[INF] $* ${plain}"; }
[[ $EUID -ne 0 ]] && LOGE "Error: Debe usar el usuario root para ejecutar este script!\n" && exit 1
if [[ ! -f /etc/openwrt_release ]]; then
    LOGE "Este script de gestión es para OpenWrt." && exit 1
fi
confirm(){ if [[ $# > 1 ]]; then echo && read -p "$1 [Por defecto $2]: " temp; if [[ x"${temp}" == x"" ]]; then temp=$2; fi; else read -p "$1 [y/n]: " temp; fi; if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then return 0; else return 1; fi; }
before_show_menu(){ echo && echo -n -e "${yellow}Presione Enter para volver al menú principal: ${plain}" && read temp && show_menu; }
check_status(){ if [[ ! -f /etc/init.d/x-ui ]]; then return 2; fi; if pgrep -f "/usr/local/x-ui/x-ui" > /dev/null; then return 0; else return 1; fi; }
check_enabled(){ if [[ -f /etc/rc.d/S99x-ui ]]; then return 0; else return 1; fi; }
start(){ check_status; if [[ $? == 0 ]]; then LOGI "El panel ya está en ejecución."; else /etc/init.d/x-ui start; sleep 2; if check_status; then LOGI "x-ui iniciado con éxito."; else LOGE "Fallo al iniciar el panel."; fi; fi; if [[ $# == 0 ]]; then before_show_menu; fi; }
stop(){ check_status; if [[ $? == 1 ]]; then LOGI "El panel ya está detenido."; else /etc/init.d/x-ui stop; sleep 2; if [[ $(check_status) -eq 1 ]]; then LOGI "x-ui detenido con éxito."; else LOGE "Fallo al detener el panel."; fi; fi; if [[ $# == 0 ]]; then before_show_menu; fi; }
restart(){ /etc/init.d/x-ui restart; sleep 2; if check_status; then LOGI "x-ui reiniciado con éxito."; else LOGE "Fallo al reiniciar el panel."; fi; if [[ $# == 0 ]]; then before_show_menu; fi; }
enable(){ /etc/init.d/x-ui enable; if [[ $? == 0 ]]; then LOGI "x-ui configurado para inicio automático."; else LOGE "Fallo al configurar el inicio automático."; fi; if [[ $# == 0 ]]; then before_show_menu; fi; }
disable(){ /etc/init.d/x-ui disable; if [[ $? == 0 ]]; then LOGI "x-ui quitado del inicio automático."; else LOGE "Fallo al quitar del inicio automático."; fi; if [[ $# == 0 ]]; then before_show_menu; fi; }
show_log(){ LOGI "Mostrando logs. Presione Ctrl+C para salir."; logread -f -e x-ui; if [[ $# == 0 ]]; then before_show_menu; fi; }
uninstall(){ confirm "Seguro que quieres desinstalar el panel?" "n"; if [[ $? != 0 ]]; then if [[ $# == 0 ]]; then show_menu; fi; return 0; fi; /etc/init.d/x-ui stop; /etc/init.d/x-ui disable; rm /etc/init.d/x-ui; rm /etc/x-ui/ -rf; rm /usr/local/x-ui/ -rf; rm /usr/bin/x-ui -f; LOGI "Desinstalación completa."; if [[ $# == 0 ]]; then before_show_menu; fi; }
show_status() { check_status; case $? in 0) echo -e "Estado: ${green}Corriendo${plain}"; check_enabled && echo -e "Inicio auto: ${green}Sí${plain}" || echo -e "Inicio auto: ${red}No${plain}";; 1) echo -e "Estado: ${yellow}Detenido${plain}"; check_enabled && echo -e "Inicio auto: ${green}Sí${plain}" || echo -e "Inicio auto: ${red}No${plain}";; 2) echo -e "Estado: ${red}No instalado${plain}";; esac; }
show_menu(){ clear; echo -e "  ${green}Script de gestión x-ui (OpenWrt)${plain}\n  ${green}0.${plain} Salir\n————————————————\n  ${green}1.${plain} Instalar x-ui\n  ${green}2.${plain} Actualizar x-ui\n  ${green}3.${plain} Desinstalar x-ui\n————————————————\n  ${green}8.${plain} Iniciar x-ui\n  ${green}9.${plain} Detener x-ui\n  ${green}10.${plain} Reiniciar x-ui\n  ${green}11.${plain} Ver estado\n  ${green}12.${plain} Ver logs\n————————————————\n  ${green}13.${plain} Habilitar inicio auto\n  ${green}14.${plain} Deshabilitar inicio auto\n"; show_status; echo && read -p "Selección [0-14]: " num; case "${num}" in 0) exit 0;; 1) bash /root/install-openwrt.sh;; 2) bash /root/install-openwrt.sh;; 3) uninstall;; 8) start;; 9) stop;; 10) restart;; 11) status && before_show_menu;; 12) show_log;; 13) enable;; 14) disable;; *) LOGE "Opción inválida";; esac; }
show_menu
EOF
    chmod +x /usr/bin/x-ui
}

# --- Función para crear el script de inicio /etc/init.d/x-ui ---
create_init_script() {
    LOGI "Creando el script de inicio procd en /etc/init.d/x-ui..."
    cat > /etc/init.d/x-ui << 'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

XUI_BIN="/usr/local/x-ui/x-ui"
XUI_DIR="/usr/local/x-ui/"

start_service() {
    [ -d "$XUI_DIR" ] || return 1
    procd_open_instance
    procd_set_param command "$XUI_BIN"
    procd_set_param workdir "$XUI_DIR"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    echo "Deteniendo el servicio x-ui..."
}

reload_service() {
    stop
    start
}
EOF
    chmod +x /etc/init.d/x-ui
}

# --- Función de Configuración Post-Instalación ---
config_after_install() {
    echo -e "${yellow}Por seguridad, es necesario configurar un usuario y puerto al finalizar.${plain}"
    read -p "Desea continuar con la configuración? [y/n]: " config_confirm
    if [[ "$config_confirm" == "y" || "$config_confirm" == "Y" ]]; then
        read -p "Introduzca el nuevo nombre de usuario: " config_account
        read -p "Introduzca la nueva contraseña: " config_password
        read -p "Introduzca el nuevo puerto de acceso al panel: " config_port
        
        LOGI "Configurando usuario, contraseña y puerto..."
        /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}"
        /usr/local/x-ui/x-ui setting -port "${config_port}"
        LOGI "Configuración completada."
    else
        LOGI "Configuración cancelada. Se usarán los valores por defecto (admin/admin, puerto 54321)."
        LOGI "Es MUY recomendable cambiarlos manualmente con el comando 'x-ui'."
    fi
}

# --- Función Principal de Instalación ---
install_x-ui() {
    LOGI "Deteniendo cualquier instancia previa de x-ui..."
    # Si el script de inicio existe, lo usa para detener el servicio
    [ -f /etc/init.d/x-ui ] && /etc/init.d/x-ui stop

    # --- INICIO DE LA CORRECCIÓN ---
    # Asegurar que el directorio de instalación /usr/local/ existe
    LOGI "Asegurando que el directorio de instalación /usr/local existe..."
    mkdir -p /usr/local/
    # --- FIN DE LA CORRECCIÓN ---

    cd /usr/local/

    # Obtener la última versión de la API de GitHub
    last_version=$(curl -Ls "https://api.github.com/repos/vaxilu/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$last_version" ]]; then
        LOGE "Fallo al detectar la última versión de x-ui. Puede ser un límite de la API de GitHub."
        exit 1
    fi
    LOGI "Última versión detectada: ${last_version}. Iniciando descarga..."

    # Descargar el binario
    wget -N --no-check-certificate -O "/usr/local/x-ui-linux-${arch}.tar.gz" "https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
    if [[ $? -ne 0 ]]; then
        LOGE "La descarga de x-ui falló. Asegúrese de que su dispositivo puede conectar con GitHub."
        exit 1
    fi

    # Descomprimir
    [[ -d /usr/local/x-ui/ ]] && rm -rf /usr/local/x-ui/
    tar -zxvf "x-ui-linux-${arch}.tar.gz" -C /usr/local/
    rm "x-ui-linux-${arch}.tar.gz"
    
    # Mover al directorio correcto si es necesario (el tarball puede crear un subdirectorio 'x-ui')
    if [[ -d /usr/local/x-ui ]]; then
        cd /usr/local/x-ui
    else
        LOGE "El directorio /usr/local/x-ui no fue encontrado después de la descompresión."
        exit 1
    fi

    chmod +x x-ui bin/xray-linux-${arch}

    # Crear los scripts necesarios
    create_init_script
    create_management_script

    # Configuración final del usuario
    config_after_install
    
    # Habilitar e iniciar el servicio
    LOGI "Habilitando el inicio automático del servicio..."
    /etc/init.d/x-ui enable
    LOGI "Iniciando el servicio x-ui..."
    /etc/init.d/x-ui start

    sleep 2
    if pgrep -f "/usr/local/x-ui/x-ui" > /dev/null; then
        LOGI "x-ui v${last_version} instalado y ejecutándose correctamente."
        LOGI "Use el comando 'x-ui' para gestionar el panel."
    else
        LOGE "El servicio x-ui no pudo iniciarse. Revise los logs con 'logread -e x-ui'."
    fi
}

# --- Inicio del Script ---
LOGI "Iniciando el proceso de instalación de x-ui para OpenWrt..."
install_x-ui
