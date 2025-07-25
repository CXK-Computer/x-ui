#!/bin/sh

#================================================================
#
#   项目名称: x-ui for OpenWrt 安装脚本
#   说    明: 本脚本基于 vaxilu/x-ui 的官方脚本修改，
#             以适配 OpenWrt 系统。
#   作    者: Gemini
#   更新日志:
#   2024-07-25 v3: 在安装前自动创建 /usr/local 目录，防止因目录不存在而出错。
#   2024-07-25 v2: 改用 'uname -m' 进行架构检测，以提高兼容性和可靠性。
#   2024-07-25 v1: 修复了 detect_arch 函数中对 opkg 架构的错误解析问题。
#
#================================================================

# Shell aRGB color codes
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 全局变量
# 在 detect_arch() 中检测并设置此变量
arch=""
# x-ui 的安装目录
xui_install_dir="/usr/local/x-ui"

# 确保脚本以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}错误: 必须使用 root 用户运行此脚本！${plain}\n"
        exit 1
    fi
}

# 检查系统是否为 OpenWrt
check_openwrt() {
    if ! grep -q "OpenWrt" /etc/os-release; then
        echo -e "${red}错误: 此脚本仅为 OpenWrt 设计。${plain}\n"
        exit 1
    fi
}

# 检测设备架构
detect_arch() {
    echo "正在检测设备架构..."
    # 使用 'uname -m' 获取架构, 这比解析 opkg 的输出更可靠
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
            arch="arm-v7"
            ;;
        armv6l)
            arch="arm-v6"
            ;;
        armv5*)
            arch="arm-v5"
            ;;
        *)
            arch=""
            ;;
    esac

    if [ -z "$arch" ]; then
        echo -e "${red}错误: 不支持的设备架构 '${raw_arch}'。${plain}"
        echo -e "${yellow}x-ui 官方没有提供适用于 MIPS 等架构的预编译文件。${plain}"
        exit 1
    fi
    echo -e "${green}检测到兼容的架构: ${arch} (基于 ${raw_arch})${plain}"
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

# 设置服务启动优先级
START=99
# 设置服务停止优先级
STOP=10

# 声明使用 procd
USE_PROCD=1
# x-ui 程序路径
PROG="/usr/local/x-ui/x-ui"
# x-ui 工作目录
RUNDIR="/usr/local/x-ui"

# procd 的启动服务函数
start_service() {
    # procd 会负责运行程序并在其崩溃时自动重启
    procd_open_instance
    # 设置要执行的命令
    procd_set_param command $PROG
    # 设置工作目录, 以便 x-ui 能找到数据库等文件
    procd_set_param workdir $RUNDIR
    # 如果服务崩溃，自动重启
    procd_set_param respawn
    # 将标准输出和错误输出重定向到系统日志
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
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
        echo -e "${yellow}账户密码设置完成${plain}"
        ${xui_install_dir}/x-ui setting -port "${config_port}"
        echo -e "${yellow}面板端口设置完成${plain}"
    else
        echo -e "${red}已取消配置。所有设置均为默认值，请尽快手动修改！${plain}"
        echo -e "${yellow}默认网页端口为 54321，用户名和密码均为 admin。${plain}"
    fi
}

# 主安装函数
install_x-ui() {
    # 如果已安装，先停止服务
    if [ -f /etc/init.d/x-ui ]; then
        echo "检测到旧版本，正在停止 x-ui 服务..."
        /etc/init.d/x-ui stop
    fi

    # 修正: 确保目标目录存在
    echo "确保安装目录 /usr/local 存在..."
    mkdir -p /usr/local

    cd /usr/local/ || exit

    local last_version
    # 如果用户没有指定版本号，就获取最新版
    if [ -z "$1" ]; then
        echo "正在检测 x-ui 最新版本..."
        last_version=$(curl -Ls "https://api.github.com/repos/vaxilu/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$last_version" ]; then
            echo -e "${red}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试。${plain}"
            exit 1
        fi
        echo -e "检测到 x-ui 最新版本：${green}${last_version}${plain}，开始安装..."
    else
        last_version=$1
        echo -e "开始安装指定版本 x-ui: ${green}v$1${plain}"
    fi

    local download_url="https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
    local file_name="x-ui-linux-${arch}.tar.gz"

    # 下载
    echo "正在从 Github 下载..."
    wget -N --no-check-certificate -O "${file_name}" "${download_url}"
    if [ $? -ne 0 ]; then
        echo -e "${red}下载 x-ui 失败，请检查网络或确保该版本存在。${plain}"
        exit 1
    fi

    # 删除旧目录
    if [ -d ${xui_install_dir} ]; then
        rm -rf ${xui_install_dir}
    fi

    # 解压
    tar -zxf "${file_name}"
    rm -f "${file_name}"
    cd "${xui_install_dir}" || exit
    chmod +x x-ui bin/xray-linux-${arch}

    # 创建 init.d 脚本
    create_init_script

    # 安装 x-ui 命令行管理工具
    echo "正在安装 x-ui 管理脚本..."
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/vaxilu/x-ui/main/x-ui.sh
    chmod +x /usr/bin/x-ui

    # 配置
    config_after_install

    # 启动服务并设置开机自启
    echo "正在启动 x-ui 服务并设置开机自启..."
    /etc/init.d/x-ui enable
    /etc/init.d/x-ui start

    echo -e "${green}x-ui v${last_version}${plain} 安装完成，面板已启动。"
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
echo "         x-ui for OpenWrt 一键安装脚本 (v3)"
echo "=============================================================="
echo ""

check_root
check_openwrt
detect_arch
install_base
install_x-ui "$1"

