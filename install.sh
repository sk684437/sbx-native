#!/bin/bash

# ============ 颜色定义 ============
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# ============ 系统环境变量 ============
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 判断域名后缀
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ hostuno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 判断下载工具
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl -so"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget -qO"
else
    red "错误: 未找到 curl 或 wget，请安装其中之一"
    exit 1
fi

# 定义工作目录和配置文件
WORKDIR="$HOME/domains/${USERNAME}.${CURRENT_DOMAIN}/public_nodejs"
ENV_FILE="${WORKDIR}/.env"
CONFIG_DIR="${HOME}/.singbox_config"

# ============ 工具函数 ============

# 创建配置目录
init_config_dir() {
    mkdir -p "$CONFIG_DIR"
}

# 加载环境变量
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
}

# 保存环境变量
save_env() {
    mkdir -p "$WORKDIR"
    cat > "$ENV_FILE" <<EOF
UUID=${UUID}
SUB_PATH=${SUB_PATH}
NEZHA_SERVER=${NEZHA_SERVER}
NEZHA_KEY=${NEZHA_KEY}
S5_PORT=${S5_PORT}
TUIC_PORT=${TUIC_PORT}
HY2_PORT=${HY2_PORT}
ANYTLS_PORT=${ANYTLS_PORT}
REALITY_PORT=${REALITY_PORT}
ARGO_DOMAIN=${ARGO_DOMAIN}
ARGO_AUTH=${ARGO_AUTH}
EOF
}

# 生成或读取UUID
get_uuid() {
    if [[ -z "$UUID" ]]; then
        export UUID=$(uuidgen -r 2>/dev/null || uuid -v 4 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    fi
}

# 生成订阅路径
get_sub_path() {
    if [[ -z "$SUB_PATH" ]]; then
        export SUB_PATH="${UUID:0:8}"
    fi
}

# 检测和管理端口
check_and_manage_ports() {
    purple "检查端口配置...\n"
    
    local port_list=$(devil port list 2>/dev/null)
    if [[ -z "$port_list" ]]; then
        red "无法获取端口列表，请检查 devil 命令"
        return 1
    fi
    
    local tcp_count=$(echo "$port_list" | grep -c "tcp")
    local udp_count=$(echo "$port_list" | grep -c "udp")
    
    # 如果端口配置不符，进行调整
    if [[ $tcp_count -ne 1 || $udp_count -lt 1 ]]; then
        yellow "端口配置需要调整...\n"
        
        # 删除多余端口
        [[ $tcp_count -gt 1 ]] && echo "$port_list" | awk '/tcp/ {print $1, $2}' | tail -n +2 | while read port type; do
            devil port del $type $port >/dev/null 2>&1
            green "删除 TCP 端口: $port"
        done
        
        [[ $udp_count -gt 2 ]] && echo "$port_list" | awk '/udp/ {print $1, $2}' | tail -n +3 | while read port type; do
            devil port del $type $port >/dev/null 2>&1
            green "删除 UDP 端口: $port"
        done
        
        # 添加缺失端口
        if [[ $tcp_count -lt 1 ]]; then
            local tcp_port=$(shuf -i 10000-65535 -n 1)
            devil port add tcp $tcp_port >/dev/null 2>&1
            green "添加 TCP 端口: $tcp_port"
        fi
        
        if [[ $udp_count -lt 2 ]]; then
            for i in {1..2}; do
                local udp_port=$(shuf -i 10000-65535 -n 1)
                devil port add udp $udp_port >/dev/null 2>&1
                green "添加 UDP 端口: $udp_port"
            done
        fi
        
        green "\n端口调整完成，请重新连接 SSH 后再运行脚本"
        return 1
    fi
    
    # 提取端口号
    export S5_PORT=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -1)
    export TUIC_PORT=$(echo "$port_list" | awk '/udp/ {print $1}' | head -1)
    export HY2_PORT=$(echo "$port_list" | awk '/udp/ {print $1}' | tail -1)
    
    purple "TCP 端口 (S5): $S5_PORT\n"
    purple "UDP 端口 (TUIC): $TUIC_PORT\n"
    purple "UDP 端口 (HY2): $HY2_PORT\n"
}

# ============ 交互函数 ============

# 配置哪吒探针
configure_nezha() {
    yellow "\n========== 哪吒探针配置 ==========\n"
    
    if [[ -n "$NEZHA_SERVER" ]]; then
        green "当前哪吒服务器: $NEZHA_SERVER"
        reading "是否修改？【y/n】: " modify
        [[ "$modify" != "y" && "$modify" != "Y" ]] && return
    fi
    
    reading "请输入哪吒服务器地址\n(格式: nezha.example.com:8008)，直接回车跳过: " input_server
    
    if [[ -z "$input_server" ]]; then
        NEZHA_SERVER=""
        NEZHA_KEY=""
        green "已跳过哪吒配置"
        return
    fi
    
    NEZHA_SERVER="$input_server"
    green "哪吒服务器: $NEZHA_SERVER"
    
    reading "请输入哪吒 NZ_CLIENT_SECRET 或 agent 密钥: " input_key
    if [[ -z "$input_key" ]]; then
        red "密钥不能为空"
        configure_nezha
        return
    fi
    
    NEZHA_KEY="$input_key"
    green "哪吒密钥已设置"
}

# 配置 Argo 隧道
configure_argo() {
    yellow "\n========== Argo 隧道配置 ==========\n"
    
    if [[ -n "$ARGO_DOMAIN" ]]; then
        green "当前 Argo 域名: $ARGO_DOMAIN"
        reading "是否修改？【y/n】: " modify
        [[ "$modify" != "y" && "$modify" != "Y" ]] && return
    fi
    
    reading "是否使用固定 Argo 隧道？【y/n】: " use_fixed
    
    if [[ "$use_fixed" != "y" && "$use_fixed" != "Y" ]]; then
        ARGO_DOMAIN=""
        ARGO_AUTH=""
        green "将使用临时隧道"
        return
    fi
    
    reading "请输入 Argo 域名: " input_domain
    if [[ -z "$input_domain" ]]; then
        red "域名不能为空"
        configure_argo
        return
    fi
    
    ARGO_DOMAIN="$input_domain"
    green "Argo 域名: $ARGO_DOMAIN"
    
    reading "请输入 Argo 认证信息 (Token 或 TunnelSecret JSON): " input_auth
    if [[ -z "$input_auth" ]]; then
        red "认证信息不能为空"
        configure_argo
        return
    fi
    
    ARGO_AUTH="$input_auth"
    green "Argo 认证已设置"
}

# 配置其他入站端口
configure_ports() {
    yellow "\n========== 其他协议端口配置 ==========\n"
    
    reading "是否配置 ANYTLS 入站端口？【y/n】: " use_anytls
    if [[ "$use_anytls" == "y" || "$use_anytls" == "Y" ]]; then
        reading "请输入 ANYTLS 端口 (空则不启用): " ANYTLS_PORT
    fi
    
    reading "是否配置 VLESS Reality 入站端口？【y/n】: " use_reality
    if [[ "$use_reality" == "y" || "$use_reality" == "Y" ]]; then
        reading "请输入 VLESS Reality 端口 (空则不启用): " REALITY_PORT
    fi
}

# 初始化配置
init_config() {
    purple "\n========== 初始化配置 ==========\n"
    
    get_uuid
    get_sub_path
    
    green "UUID: $UUID"
    green "订阅路径: $SUB_PATH\n"
    
    reading "是否自定义订阅路径？【y/n】: " custom_sub
    if [[ "$custom_sub" == "y" || "$custom_sub" == "Y" ]]; then
        reading "请输入新的订阅路径 (不要加 /): " new_sub
        [[ -n "$new_sub" ]] && SUB_PATH="${new_sub#/}"
    fi
    
    configure_nezha
    configure_argo
    configure_ports
    
    save_env
    green "\n配置已保存"
}

# ============ 服务管理 ============

install_service() {
    purple "\n========== 安装服务 ==========\n"
    
    check_and_manage_ports || return 1
    
    if [[ ! -f "$ENV_FILE" ]]; then
        init_config
    else
        load_env
        yellow "检测到已有配置\n"
        reading "是否重新配置？【y/n】: " reconfig
        if [[ "$reconfig" == "y" || "$reconfig" == "Y" ]]; then
            init_config
        else
            green "使用现有配置"
        fi
    fi
    
    yellow "\n正在安装服务...\n"
    
    # 删除旧服务
    devil www del ${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
    rm -rf ${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
    
    # 创建新服务
    mkdir -p "$WORKDIR"
    devil www add ${USERNAME}.${CURRENT_DOMAIN} nodejs /usr/local/bin/node24 >/dev/null 2>&1
    
    # 下载文件
    yellow "下载应用文件...\n"
    $DOWNLOAD_CMD "${WORKDIR}/app.js" "https://raw.githubusercontent.com/sk684437/sbx-native/refs/heads/serv00/ct8/nodejs/index.js" 2>/dev/null
    
    mkdir -p "${WORKDIR}/public"
    $DOWNLOAD_CMD "${WORKDIR}/public/index.html" "https://raw.githubusercontent.com/sk684437/nodejs-argo/refs/heads/main/index.html" 2>/dev/null
    
    # 配置 npm
    ln -fs /usr/local/bin/node24 ~/bin/node 2>/dev/null
    ln -fs /usr/local/bin/npm24 ~/bin/npm 2>/dev/null
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global' 2>/dev/null
    
    if ! grep -q "npm-global/bin" "$HOME/.bash_profile" 2>/dev/null; then
        echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile
    fi
    source $HOME/.bash_profile 2>/dev/null
    
    # 安装依赖
    yellow "安装依赖...\n"
    cd ${WORKDIR} && npm install dotenv axios koffi --silent 2>/dev/null
    
    # 启动服务
    yellow "启动服务...\n"
    devil www restart ${USERNAME}.${CURRENT_DOMAIN} >/dev/null 2>&1
    sleep 3
    
    # 验证服务
    if curl -o /dev/null -m 5 -s -w "%{http_code}" "https://${USERNAME}.${CURRENT_DOMAIN}" 2>/dev/null | grep -q "200"; then
        green "\n✅ 服务安装成功\n"
        display_subscription_info
    else
        red "\n❌ 服务启动失败"
        red "请检查:"
        red "  - 域名: ${USERNAME}.${CURRENT_DOMAIN}"
        red "  - 端口配置"
        red "  - 运行: devil www restart ${USERNAME}.${CURRENT_DOMAIN}"
    fi
}

uninstall_service() {
    yellow "\n========== 卸载服务 ==========\n"
    
    reading "确定卸载吗？【y/n】: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    yellow "正在卸载...\n"
    
    devil www del ${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
    rm -rf ${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
    rm -rf "${HOME}/bin/00" 2>/dev/null || true
    rm -f "$ENV_FILE" 2>/dev/null || true
    
    sed -i '/singbox/d' "${HOME}/.bashrc" 2>/dev/null
    
    green "✅ 卸载完成"
}

reset_system() {
    yellow "\n========== 初始化系统 ==========\n"
    
    reading "确定重置系统吗？【y/n】: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    
    yellow "正在初始化...\n"
    
    devil www list 2>/dev/null | awk 'NF>=2 && $1 ~ /\./ {print $1}' | while read -r domain; do
        devil www del "$domain" 2>/dev/null || true
    done
    
    rm -rf $HOME/domains/* 2>/dev/null || true
    rm -rf "${CONFIG_DIR}" 2>/dev/null || true
    
    green "✅ 系统初始化完成"
}

# ============ 显示函数 ============

display_subscription_info() {
    if [[ -f "$ENV_FILE" ]]; then
        load_env
        echo ""
        green "========== 订阅信息 =========="
        green "域名: https://${USERNAME}.${CURRENT_DOMAIN}"
        green "订阅路径: ${SUB_PATH}"
        green "完整订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/${SUB_PATH}"
        echo ""
        
        if [[ -n "$NEZHA_SERVER" ]]; then
            green "✓ 哪吒面板: $NEZHA_SERVER"
        fi
        
        if [[ -n "$ARGO_DOMAIN" ]]; then
            green "✓ Argo 隧道: $ARGO_DOMAIN"
        else
            yellow "○ 使用临时 Argo 隧道"
        fi
        
        [[ -n "$S5_PORT" ]] && green "✓ SOCKS5 端口: $S5_PORT"
        [[ -n "$TUIC_PORT" ]] && green "✓ TUIC 端口: $TUIC_PORT"
        [[ -n "$HY2_PORT" ]] && green "✓ Hysteria2 端口: $HY2_PORT"
        [[ -n "$ANYTLS_PORT" ]] && green "✓ AnyTLS 端口: $ANYTLS_PORT"
        [[ -n "$REALITY_PORT" ]] && green "✓ VLESS Reality 端口: $REALITY_PORT"
        echo ""
    else
        red "未找到配置文件"
    fi
}

view_config() {
    display_subscription_info
}

# ============ 快捷命令 ============

setup_quick_command() {
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/00" <<'EOF'
#!/bin/bash
bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_serv00.sh)
EOF
    chmod +x "$HOME/bin/00"
    
    if ! grep -q "HOME/bin" "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    
    green "快捷命令 '00' 创建成功"
}

# ============ 主菜单 ============

show_menu() {
    clear
    echo ""
    purple "╔════════════════════════════════════════════╗"
    purple "║   Serv00|Ct8|HostUNO Sing-Box 管理脚本    ║"
    purple "╚════════════════════════════════════════════╝"
    echo ""
    echo -e "${green}频道: ${yellow}https://youtube.com/@eooce${re}"
    echo -e "${green}群组: ${yellow}https://t.me/eooceu${re}"
    echo ""
    echo -e "${yellow}快捷命令: ${green}00${re}"
    echo ""
    echo -e "${green}1. 安装服务${re}"
    echo -e "${red}2. 卸载服务${re}"
    echo -e "${green}3. 查看配置${re}"
    echo -e "${yellow}4. 初始化系统${re}"
    echo -e "${red}0. 退出${re}"
    echo ""
    reading "请选择 [0-4]: " choice
    echo ""
}

main() {
    init_config_dir
    setup_quick_command
    
    while true; do
        show_menu
        case "${choice}" in
            1) install_service ;;
            2) uninstall_service ;;
            3) view_config ;;
            4) reset_system ;;
            0) green "再见"; exit 0 ;;
            *) red "无效选项，请重试" ;;
        esac
        
        reading "\n按 Enter 继续..." wait_key
    done
}

main
