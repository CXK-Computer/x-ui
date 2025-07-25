#!/bin/sh

#================================================================
#
#   项目名称: x-ui for OpenWrt 安装脚本
#   说    明: 本脚本为本地安装版，需要您预先下载好安装文件。
#   作    者: Gemini
#   更新日志:
#   2024-07-25 v18: 智能路径版。当 /usr/local 空间不足时，允许用户选择
#                   安装到 /tmp 目录（非持久化），并增加明确风险提示。
#   2024-07-25 v17: 最终诊断版。重写空间检查逻辑。
#
#================================================================

# Shell aRGB color codes
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# --- 全局变量 ---
REPO_OWNER="FranzKafkaYu"
arch=""
# xui_install_dir 变量将由 determine_install_path 函数动态设置
xui_install_dir=""

# 确保脚本以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}错误: 必须使用 root 用户运行此脚本！${plain}\n"
        exit 1
    fi
}

# 检查系统是否为 OpenWrt (增强版)
check_openwrt() {
    echo "正在检查系统类型..."
    if [ -f /etc/os-release ] && grep -q "OpenWrt" /etc/os-release; then
        echo -e "${green}检测到 OpenWrt 系统。${plain}"
    elif [ -f /etc/config/system ]; then
        echo -e "${yellow}警告: /etc/os-release 中未找到 'OpenWrt' 标识。但检测到 /etc/config/system，继续执行...${plain}"
    else
        echo -e "${red}错误: 未能识别到 OpenWrt 系统。${plain}"
        exit 1
    fi
}

# 检测设备架构
detect_arch() {
    echo "正在检测设备架构..."
    local raw_arch
    raw_arch=$(uname -m)

    case "$raw_arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        armv7l)
            arch="armv7"
            ;;
        armv6l)
            arch="armv6"
            ;;
        armv5*)
            arch="armv5"
            ;;
        *)
            arch=""
            ;;
    esac

    if [ -z "$arch" ]; then
        echo -e "${red}错误: 不支持的设备架构 '${raw_arch}'。${plain}"
        exit 1
    fi
    echo -e "${green}检测到兼容的架构: ${arch} (基于 ${raw_arch})${plain}"
}

# 决定安装路径，如果空间不足则警告
determine_install_path() {
    echo "正在确定最佳安装路径..."
    
    local required_space=40960 # 解压需要约 40MB
    local preferred_parent_dir="/usr/local"
    local fallback_parent_dir="/tmp"

    # 1. 检查首选的持久化存储路径 /usr/local
    mkdir -p ${preferred_parent_dir}
    local available_preferred_space
    available_preferred_space=$(df -k ${preferred_parent_dir} | awk 'NR==2 {print $4}')

    if [ "$available_preferred_space" -ge "$required_space" ]; then
        xui_install_dir="${preferred_parent_dir}/x-ui"
        echo -e "${green}检测到 ${preferred_parent_dir} 空间充足，将安装于此 (持久化存储)。${plain}"
        return
    fi

    # 2. 如果首选路径空间不足，检查备用的临时存储路径 /tmp
    echo -e "${yellow}警告: ${preferred_parent_dir} 空间不足 (可用: ${available_preferred_space}KB, 需要: ${required_space}KB)。${plain}"
    echo "正在检查 ${fallback_parent_dir} 目录作为备选方案..."
    
    local available_fallback_space
    available_fallback_space=$(df -k ${fallback_parent_dir} | awk 'NR==2 {print $4}')

    if [ "$available_fallback_space" -ge "$required_space" ]; then
        xui_install_dir="${fallback_parent_dir}/x-ui"
        echo -e "${red}==================== 重要警告 ====================${plain}"
        echo -e "${yellow}备选方案: ${fallback_parent_dir} 目录空间充足，将安装于此。${plain}"
        echo -e "${yellow}但请注意: ${fallback_parent_dir} 目录位于内存中，这意味着${plain}"
        echo -e "${red}设备重启后，x-ui 程序及其所有配置都将丢失！${plain}"
        echo -e "${yellow}这只应作为临时解决方案。${plain}"
        echo -e "${red}==================================================${plain}"
        echo -n "您是否理解风险并希望继续? [y/n]: "
        read -r confirm_tmp
        if [ "$confirm_tmp" != "y" ] && [ "$confirm_tmp" != "Y" ]; then
            echo "安装已取消。"
            exit 1
        fi
        return
    fi
    
    # 3. 如果两个位置都没有足够空间
    echo -e "${red}错误: 两个检查路径 (/usr/local 和 /tmp) 均无足够空间！${plain}"
    echo -e "请清理您设备的存储空间，或将 OpenWrt 系统安装到外置 USB 存储设备上以获取更多空间。"
    exit 1
}

# 使用 opkg 安装基础依赖
install_base() {
    echo "正在安装依赖包 (wget, curl, tar)..."
    opkg update
    if ! opkg install wget curl tar; then
        echo -e "${red}依赖包安装失败，请检查 opkg 源或网络连接。${plain}"
        exit 1
    fi
}

# 创建 procd 使用的 init.d 脚本
create_init_script() {
    echo "正在创建 procd 使用的 init.d 启动脚本..."
    cat > /etc/init.d/x-ui <<'EOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1
PROG="__PROG_PATH__"
RUNDIR="__RUNDIR_PATH__"
start_service() {
    procd_open_instance
    procd_set_param command $PROG
    procd_set_param workdir $RUNDIR
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    # 将占位符替换为动态确定的安装路径
    sed -i "s|__PROG_PATH__|${xui_install_dir}/x-ui|g" /etc/init.d/x-ui
    sed -i "s|__RUNDIR_PATH__|${xui_install_dir}|g" /etc/init.d/x-ui

    chmod +x /etc/init.d/x-ui
    echo -e "${green}init.d 脚本创建成功。${plain}"
}

# 安装/更新后，强制用户修改默认配置
config_after_install() {
    echo -e "${yellow}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${plain}"
    echo -n "是否现在进行配置? [y/n]: "
    read -r config_confirm
    if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
        echo -n "请输入新的面板登录用户名: "
        read -r config_account
        echo -e "${yellow}用户名将设置为: ${config_account}${plain}"
        echo -n "请输入新的面板登录密码: "
        read -r config_password
        echo -e "${yellow}密码将设置为: ${config_password}${plain}"
        echo -n "请输入新的面板访问端口: "
        read -r config_port
        echo -e "${yellow}面板端口将设置为: ${config_port}${plain}"
        echo -e "${yellow}正在应用设置...${plain}"
        ${xui_install_dir}/x-ui setting -username "${config_account}" -password "${config_password}"
        ${xui_install_dir}/x-ui setting -port "${config_port}"
        echo -e "${green}账户和端口设置完成。${plain}"
    else
        echo -e "${red}已取消配置。所有设置均为默认值，请尽快手动修改！${plain}"
    fi
}

# 主安装函数
install_x-ui() {
    # 如果已安装，先停止服务
    if [ -f /etc/init.d/x-ui ]; then
        echo "检测到旧版本，正在停止 x-ui 服务..."
        /etc/init.d/x-ui stop
    fi
    
    local version="0.3.4.4"
    local download_url="https://github.com/${REPO_OWNER}/x-ui/releases/download/${version}/x-ui-linux-${arch}.tar.gz"
    local file_name="x-ui-linux-${arch}.tar.gz"
    local file_path="/tmp/${file_name}"

    # 下载到 /tmp 目录
    cd /tmp || exit

    echo "正在从 Github 直接下载文件到 /tmp 目录..."
    wget --no-check-certificate -O "${file_path}" "${download_url}"
    if [ $? -ne 0 ]; then
        echo -e "${red}下载 x-ui 失败，请检查网络或确保该版本/架构存在。${plain}"
        exit 1
    fi
    echo -e "${green}文件下载成功。${plain}"

    # 准备安装目录并解压
    local install_parent_dir
    install_parent_dir=$(dirname "$xui_install_dir")
    echo "正在准备安装目录 (${install_parent_dir}) 并解压文件..."
    mkdir -p "${install_parent_dir}"
    if [ -d "${xui_install_dir}" ]; then
        rm -rf "${xui_install_dir}"
    fi
    tar -zxf "${file_path}" -C "${install_parent_dir}"
    
    # 清理下载的临时文件
    rm -f "${file_path}"
    
    cd "${xui_install_dir}" || exit
    chmod +x x-ui bin/xray-linux-${arch}
    echo -e "${green}文件解压和安装完成。${plain}"

    # 创建服务并配置
    create_init_script

    # 安装管理脚本
    echo "正在安装 x-ui 管理脚本..."
    wget --no-check-certificate -O /usr/bin/x-ui "https://raw.githubusercontent.com/FranzKafkaYu/x-ui/main/x-ui.sh"
    if [ $? -ne 0 ]; then
        echo -e "${red}下载 x-ui 管理脚本失败，可跳过。${plain}"
    else
        chmod +x /usr/bin/x-ui
    fi

    config_after_install

    # 启动服务
    echo "正在启动 x-ui 服务并设置开机自启..."
    /etc/init.d/x-ui enable
    /etc/init.d/x-ui start

    echo -e "${green}x-ui v${version}${plain} 安装完成，面板已启动。"
    echo -e ""
    echo -e "x-ui 管理脚本使用方法 (在 SSH 中执行): "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单 (功能更多)"
    echo -e "x-ui start        - 启动 x-ui 面板"
    echo -e "x-ui stop         - 停止 x-ui 面板"
    echo -e "x-ui restart      - 重启 x-ui 面板"
    echo -e "x-ui status       - 查看 x-ui 状态"
    echo -e "x-ui enable       - 设置 x-ui 开机自启"
    echo -e "x-ui disable      - 取消 x-ui 开机自启"
    echo -e "x-ui log          - 查看 x-ui 日志"
    echo -e "x-ui update       - 更新 x-ui 面板"
    echo -e "x-ui install      - 安装 x-ui 面板"
    echo -e "x-ui uninstall    - 卸载 x-ui 面板"
    echo -e "----------------------------------------------"
}

# --- 脚本执行入口 ---
clear
echo "=============================================================="
echo "         x-ui for OpenWrt 一键安装脚本 (v18-智能路径版)"
echo "=============================================================="
echo ""

check_root
check_openwrt
detect_arch
# 移除了 install_base 和 check_disk_space, 将在主函数中调用
install_base
determine_install_path
install_x-ui "$1"

