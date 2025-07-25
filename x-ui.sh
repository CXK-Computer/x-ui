#!/bin/bash

# Este script debe ejecutarse con 'bash', no 'sh'.

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Funciones de log
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

# Comprobar root
[[ $EUID -ne 0 ]] && LOGE "Error: Debe usar el usuario root para ejecutar este script.\n" && exit 1

# Comprobar OS
if [[ -f /etc/openwrt_release ]]; then
    release="openwrt"
elif cat /etc/issue | grep -Eqi "debian|ubuntu"; then
    LOGE "Este script está adaptado para OpenWrt. Detectado sistema Debian/Ubuntu."
    exit 1
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    LOGE "Este script está adaptado para OpenWrt. Detectado sistema CentOS."
    exit 1
else
    LOGE "Sistema operativo no detectado. Este script es para OpenWrt.\n" && exit 1
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Por defecto $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Desea reiniciar el panel? Esto también reiniciará xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Presione Enter para volver al menú principal: ${plain}" && read temp
    show_menu
}

install() {
    LOGI "Iniciando la instalación de x-ui..."
    LOGI "Asegúrese de haber instalado 'bash', 'curl' y 'wget' con opkg."
    
    # El script de instalación oficial podría funcionar si solo descarga binarios.
    # Si intenta usar systemd, fallará. El script init.d se encargará del servicio.
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "La instalación base parece haber funcionado. Ahora habilitando el servicio con procd."
        # Habilitar el servicio para que inicie con el sistema
        /etc/init.d/x-ui enable
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    else
        LOGE "El script de instalación falló. Compruebe los logs."
    fi
}

update() {
    confirm "Esto reinstalará la versión más reciente, los datos no se perderán. Continuar?" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelado"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "Actualización completa, reiniciando el panel..."
        restart
        exit 0
    fi
}

uninstall() {
    confirm "Seguro que quieres desinstalar el panel y xray?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /etc/init.d/x-ui stop
    /etc/init.d/x-ui disable
    rm /etc/init.d/x-ui
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    LOGI "Desinstalación completa."
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "Seguro que quiere resetear el usuario y contraseña a 'admin'?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -username admin -password admin
    echo -e "Usuario y contraseña reseteados a ${green}admin${plain}. Por favor, reinicie el panel."
    confirm_restart
}

reset_config() {
    confirm "Seguro que quiere resetear toda la configuración del panel? (los datos de usuario no se perderán)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "Configuración reseteada. Reinicie el panel y use el puerto por defecto ${green}54321${plain}."
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "Error obteniendo la configuración. Revise los logs."
        show_menu
    fi
    LOGI "${info}"
}


set_port() {
    echo && echo -n -e "Introduzca el número de puerto [1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelado"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "Puerto configurado. Reinicie el panel y use el nuevo puerto ${green}${port}${plain}."
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        LOGI "El panel ya está en ejecución."
    else
        /etc/init.d/x-ui start
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui iniciado con éxito."
        else
            LOGE "Fallo al iniciar el panel. Revise los logs con 'logread'."
        fi
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        LOGI "El panel ya está detenido."
    else
        /etc/init.d/x-ui stop
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui detenido con éxito."
        else
            LOGE "Fallo al detener el panel."
        fi
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    /etc/init.d/x-ui restart
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui y xray reiniciados con éxito."
    else
        LOGE "Fallo al reiniciar el panel. Revise los logs con 'logread'."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    check_status > /dev/null
    case $? in
    0)
        LOGI "Estado del panel: Corriendo"
        ;;
    1)
        LOGI "Estado del panel: Detenido"
        ;;
    2)
        LOGI "Estado del panel: No instalado"
        ;;
    esac
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    /etc/init.d/x-ui enable
    if [[ $? == 0 ]]; then
        LOGI "x-ui configurado para inicio automático."
    else
        LOGE "Fallo al configurar el inicio automático."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    /etc/init.d/x-ui disable
    if [[ $? == 0 ]]; then
        LOGI "x-ui quitado del inicio automático."
    else
        LOGE "Fallo al quitar del inicio automático."
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    LOGI "Mostrando logs para x-ui. Presione Ctrl+C para salir."
    logread -f -e x-ui
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 0: corriendo, 1: no corriendo, 2: no instalado
check_status() {
    if [[ ! -f /etc/init.d/x-ui ]]; then
        return 2
    fi
    if pgrep -f "/usr/local/x-ui/x-ui" > /dev/null; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    if [[ -f /etc/rc.d/S99x-ui ]]; then
        return 0
    else
        return 1
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Estado del panel: ${green}Corriendo${plain}"
        show_enable_status
        ;;
    1)
        echo -e "Estado del panel: ${yellow}Detenido${plain}"
        show_enable_status
        ;;
    2)
        echo -e "Estado del panel: ${red}No instalado${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Inicio automático: ${green}Sí${plain}"
    else
        echo -e "Inicio automático: ${red}No${plain}"
    fi
}

check_xray_status() {
    # Asumimos que xray es un subproceso de x-ui o se llama de forma similar
    if pgrep -f "xray-linux" > /dev/null; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "Estado de Xray: ${green}Corriendo${plain}"
    else
        echo -e "Estado de Xray: ${red}No corriendo${plain}"
    fi
}

# Las funciones no compatibles se dejan fuera o se marcan como no disponibles.
install_bbr() {
    LOGE "La instalación de BBR no es aplicable en OpenWrt desde este script."
    before_show_menu
}

ssl_cert_issue() {
    LOGW "La solicitud de certificados con acme.sh puede requerir dependencias adicionales."
    LOGW "Asegúrese de tener 'socat' y otras herramientas instaladas vía opkg."
    confirm "Desea continuar?" "n"
    if [[ $? != 0 ]]; then
        show_menu
        return
    fi
    # El resto de la función puede funcionar si las dependencias están cubiertas.
    # ... (código original de ssl_cert_issue)
}


show_menu() {
    clear
    echo -e "
  ${green}Script de gestión del panel x-ui (Adaptado para OpenWrt)${plain}
  ${green}0.${plain} Salir del script
————————————————
  ${green}1.${plain} Instalar x-ui
  ${green}2.${plain} Actualizar x-ui
  ${green}3.${plain} Desinstalar x-ui
————————————————
  ${green}4.${plain} Resetear usuario y contraseña
  ${green}5.${plain} Resetear configuración del panel
  ${green}6.${plain} Configurar puerto del panel
  ${green}7.${plain} Ver configuración actual del panel
————————————————
  ${green}8.${plain} Iniciar x-ui
  ${green}9.${plain} Detener x-ui
  ${green}10.${plain} Reiniciar x-ui
  ${green}11.${plain} Ver estado de x-ui
  ${green}12.${plain} Ver logs de x-ui
————————————————
  ${green}13.${plain} Habilitar inicio automático
  ${green}14.${plain} Deshabilitar inicio automático
————————————————
  ${green}15.${plain} Instalar BBR (No disponible en OpenWrt)
  ${green}16.${plain} Solicitar certificado SSL (acme)
 "
    show_status
    echo && read -p "Introduzca su selección [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1) install ;;
    2) update ;;
    3) uninstall ;;
    4) reset_user ;;
    5) reset_config ;;
    6) set_port ;;
    7) check_config ;;
    8) start ;;
    9) stop ;;
    10) restart ;;
    11) status ;;
    12) show_log ;;
    13) enable ;;
    14) disable ;;
    15) install_bbr ;;
    16) ssl_cert_issue ;;
    *)
        LOGE "Por favor, introduzca un número válido [0-16]"
        ;;
    esac
}

# Main
if [[ $# > 0 ]]; then
    # El manejo de argumentos se puede mantener si es útil
    case $1 in
    "start") start 0 ;;
    "stop") stop 0 ;;
    "restart") restart 0 ;;
    "status") status 0 ;;
    "enable") enable 0 ;;
    "disable") disable 0 ;;
    "log") show_log 0 ;;
    "update") update 0 ;;
    "install") install 0 ;;
    "uninstall") uninstall 0 ;;
    *) show_menu ;;
    esac
else
    show_menu
fi
