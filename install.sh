#!/bin/bash

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
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export UUID=${UUID:-$(uuidgen -r)}  
export SUB_PATH=${SUB_PATH:-${UUID:0:8}}
if [[ "$HOSTNAME" =~ ct8 ]]; then CURRENT_DOMAIN="ct8.pl"; elif [[ "$HOSTNAME" =~ hostuno ]]; then CURRENT_DOMAIN="useruno.com"; else CURRENT_DOMAIN="serv00.net"; fi
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { red "Error: neither curl nor wget found, please install one of them." >&2; exit 1; }
WORKDIR="$HOME/domains/${USERNAME}.${CURRENT_DOMAIN}/public_nodejs"
ENV_FILE="${WORKDIR}/.env"

check_port () {
port_list=$(devil port list)
tcp_ports=$(echo "$port_list" | grep -c "tcp")
udp_ports=$(echo "$port_list" | grep -c "udp")
if [[ $tcp_ports -ne 1 || $udp_ports -ne 2 ]]; then
    red "端口规则不符合要求，正在调整..."
    if [[ $tcp_ports -gt 1 ]]; then
        tcp_to_delete=$((tcp_ports - 1))
        echo "$port_list" | awk '/tcp/ {print $1, $2}' | head -n $tcp_to_delete | while read port type; do
            devil port del $type $port >/dev/null 2>&1
            green "已删除TCP端口: $port"
        done
    fi

    if [[ $udp_ports -gt 2 ]]; then
        udp_to_delete=$((udp_ports - 2))
        echo "$port_list" | awk '/udp/ {print $1, $2}' | head -n $udp_to_delete | while read port type; do
            devil port del $type $port >/dev/null 2>&1
            green "已删除UDP端口: $port"
        done
    fi

    if [[ $tcp_ports -lt 1 ]]; then
        while true; do
            tcp_port=$(shuf -i 10000-65535 -n 1) 
            result=$(devil port add tcp $tcp_port 2>&1)
            if [[ $result == *"Ok"* ]]; then
                green "已添加TCP端口: $tcp_port"
                break
            else
                yellow "端口 $tcp_port 不可用，尝试其他端口..."
            fi
        done
    fi

    if [[ $udp_ports -lt 2 ]]; then
        udp_ports_to_add=$((2 - udp_ports))
        udp_ports_added=0
        while [[ $udp_ports_added -lt $udp_ports_to_add ]]; do
            udp_port=$(shuf -i 10000-65535 -n 1) 
            result=$(devil port add udp $udp_port 2>&1)
            if [[ $result == *"Ok"* ]]; then
                green "已添加UDP端口: $udp_port"
                if [[ $udp_ports_added -eq 0 ]]; then
                    udp_port1=$udp_port
                else
                    udp_port2=$udp_port
                fi
                udp_ports_added=$((udp_ports_added + 1))
            else
                yellow "端口 $udp_port 不可用，尝试其他端口..."
            fi
        done
    fi
    green "端口已调整完成,将断开ssh连接,请重新连接shh重新执行脚本"
    quick_command
    devil binexec on >/dev/null 2>&1
    kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
else
    tcp_port=$(echo "$port_list" | awk '/tcp/ {print $1}')
    udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
    udp_port1=$(echo "$udp_ports" | sed -n '1p')
    udp_port2=$(echo "$udp_ports" | sed -n '2p')
fi
purple "vmess-argo使用的tcp端口为: $tcp_port"
purple "tuic和hy2使用的udp端口分别为: $udp_port1 和 $udp_port2"
export ARGO_PORT=$tcp_port
export TUIC_PORT=$udp_port1
export HY2_PORT=$udp_port2
}

# ------------------------------------------------------------------
# 读取已有 .env 中的配置，作为"沿用原配置"时的默认值来源
# ------------------------------------------------------------------
load_existing_config() {
  OLD_UUID=""; OLD_SUB_PATH=""
  OLD_NEZHA_SERVER=""; OLD_NEZHA_PORT=""; OLD_NEZHA_KEY=""
  OLD_TG_CHAT_ID=""; OLD_TG_TOKEN=""
  OLD_ARGO_DOMAIN=""; OLD_ARGO_AUTH=""

  [[ -f "$ENV_FILE" ]] || return

  OLD_UUID=$(sed -n 's/^UUID=\(.*\)/\1/p' "$ENV_FILE")
  OLD_SUB_PATH=$(sed -n 's/^SUB_PATH=\(.*\)/\1/p' "$ENV_FILE")
  OLD_NEZHA_SERVER=$(sed -n 's/^NEZHA_SERVER=\(.*\)/\1/p' "$ENV_FILE")
  OLD_NEZHA_PORT=$(sed -n 's/^NEZHA_PORT=\(.*\)/\1/p' "$ENV_FILE")
  OLD_NEZHA_KEY=$(sed -n 's/^NEZHA_KEY=\(.*\)/\1/p' "$ENV_FILE")
  OLD_TG_CHAT_ID=$(sed -n 's/^TG_CHAT_ID=\(.*\)/\1/p' "$ENV_FILE")
  OLD_TG_TOKEN=$(sed -n 's/^TG_TOKEN=\(.*\)/\1/p' "$ENV_FILE")
  OLD_ARGO_DOMAIN=$(sed -n 's/^ARGO_DOMAIN=\(.*\)/\1/p' "$ENV_FILE")
  OLD_ARGO_AUTH=$(sed -n 's/^ARGO_AUTH=\(.*\)/\1/p' "$ENV_FILE")
}

read_variables() {
  # ---------------- 哪吒探针 ----------------
  if [[ -n "$OLD_NEZHA_SERVER" || -n "$OLD_NEZHA_KEY" ]]; then
    yellow "\n检测到已配置哪吒探针:"
    green "  域名/IP: ${OLD_NEZHA_SERVER}"
    [[ -n "$OLD_NEZHA_PORT" ]] && green "  端口: ${OLD_NEZHA_PORT}"
    reading "是否修改哪吒探针配置？(直接回车则不修改,沿用原配置)【y/n】: " nz_modify
    if [[ "$nz_modify" != "y" && "$nz_modify" != "Y" ]]; then
      NEZHA_SERVER="$OLD_NEZHA_SERVER"
      NEZHA_PORT="$OLD_NEZHA_PORT"
      NEZHA_KEY="$OLD_NEZHA_KEY"
      green "已沿用原哪吒探针配置\n"
    else
      nezha_prompt
    fi
  else
    reading "是否需要安装哪吒探针？(直接回车则不安装)【y/n】: " nz_choice
    if [[ "$nz_choice" == "y" || "$nz_choice" == "Y" ]]; then
      nezha_prompt
    fi
  fi

  # ---------------- Telegram 通知 ----------------
  if [[ -n "$OLD_TG_CHAT_ID" ]]; then
    yellow "\n检测到已配置Telegram通知:"
    green "  chat_id: ${OLD_TG_CHAT_ID}"
    reading "是否修改Telegram通知配置？(直接回车则不修改,沿用原配置)【y/n】: " tg_modify
    if [[ "$tg_modify" != "y" && "$tg_modify" != "Y" ]]; then
      tg_chat_id="$OLD_TG_CHAT_ID"
      tg_token="$OLD_TG_TOKEN"
      green "已沿用原Telegram通知配置\n"
    else
      tg_prompt
    fi
  else
    reading "是否需要Telegram通知？(直接回车则不启用)【y/n】: " tg_notification
    if [[ "$tg_notification" == "y" || "$tg_notification" == "Y" ]]; then
      tg_prompt
    fi
  fi
}

nezha_prompt() {
  reading "\n请输入哪吒探针域名或ip\nv1哪吒形式：nezha.abc.com:8008,v0哪吒形式：nezha.abc.com ：" NEZHA_SERVER
  green "你的哪吒域名为: $NEZHA_SERVER"
  if [[ "$NEZHA_SERVER" != *":"* ]]; then
    reading "请输入哪吒v0探针端口(直接回车将设置为5555)：" NEZHA_PORT
    [[ -z $NEZHA_PORT ]] && NEZHA_PORT="5555"
    green "你的哪吒端口为: $NEZHA_PORT"
  else
    NEZHA_PORT=""
  fi
  reading "请输入v0的agent密钥或v1的NZ_CLIENT_SECRET：" NEZHA_KEY
  green "你的哪吒密钥为: $NEZHA_KEY"
}

tg_prompt() {
  reading "请输入Telegram chat ID (tg上@laowang_serv00_bot获取): " tg_chat_id
  [[ -z $tg_chat_id ]] && { red "Telegram chat ID不能为空"; return; }
  green "你设置的Telegram chat_id为: ${tg_chat_id}"

  reading "请输入Telegram Bot Token (直接回车使用老王的bot通知或填写自己的): " tg_token
  [[ -z $tg_token ]] && tg_token=""
  green "你设置的Telegram bot token为: ${tg_token}"
}

install_singbox() {
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
echo -e "${yellow}本脚本同时四协议共存${purple}(vmess-ws,vmess-ws-tls(argo),hysteria2,tuic)${re}"
reading "\n确定继续安装吗？(直接回车即确认安装)【y/n】: " choice
  case "${choice:-y}" in
    [Yy]|"")
    	clear
        load_existing_config
        check_port
        read_variables
        argo_configure
        install_service
      ;;
    [Nn]) exit 0 ;;
    *) red "无效的选择，请输入y或n" && menu ;;
  esac
}


uninstall_singbox() {
  reading "\n确定要卸载吗？【y/n】: " choice
    case "$choice" in
        [Yy])
	          bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
            devil www del ${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
            rm -rf ${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN} 2>/dev/null || true
            rm -rf "${HOME}/bin/00" >/dev/null 2>&1
            [ -d "${HOME}/bin" ] && [ -z "$(ls -A "${HOME}/bin")" ] && rmdir "${HOME}/bin"
            sed -i '/export PATH="\$HOME\/bin:\$PATH"/d' "${HOME}/.bashrc" >/dev/null 2>&1
            source "${HOME}/.bashrc"
	          clear
       	    green "代理和哪吒服务已完全卸载"
          ;;
        [Nn]) exit 0 ;;
    	  *) red "无效的选择,请输入y或n" && menu ;;
    esac
}

reset_system() {
reading "\n确定重置系统吗吗？【y/n】: " choice
  case "$choice" in
    [Yy]) yellow "\n初始化系统中,请稍后...\n"
          bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
          find "${HOME}" -mindepth 1 ! -name "domains" ! -name "mail" ! -name "repo" ! -name "backups" -exec rm -rf {} + > /dev/null 2>&1
          devil www list | awk 'NF>=2 && $1 ~ /\./ {print $1}' | while read -r domain; do devil www del "$domain"; done
          rm -rf $HOME/domains/* > /dev/null 2>&1
          green "\n初始化系统完成!\n"
         ;;
       *) menu ;;
  esac
}

argo_configure() {
  if [[ -n "$OLD_ARGO_DOMAIN" || -n "$OLD_ARGO_AUTH" ]]; then
    yellow "\n检测到已配置固定argo隧道:"
    green "  域名: ${OLD_ARGO_DOMAIN}"
    reading "是否修改argo固定隧道配置？(直接回车则不修改,沿用原配置)【y/n】: " argo_modify
    if [[ "$argo_modify" != "y" && "$argo_modify" != "Y" ]]; then
      ARGO_DOMAIN="$OLD_ARGO_DOMAIN"
      ARGO_AUTH="$OLD_ARGO_AUTH"
      green "已沿用原argo固定隧道配置\n"
      generate_argo_files
      return
    fi
  fi

  reading "是否需要使用固定argo隧道？(直接回车将使用临时隧道)【y/n】: " argo_choice
  [[ -z $argo_choice ]] && { ARGO_DOMAIN=""; ARGO_AUTH=""; return; }
  [[ "$argo_choice" != "y" && "$argo_choice" != "Y" && "$argo_choice" != "n" && "$argo_choice" != "N" ]] && { red "无效的选择, 请输入y或n"; return; }
  if [[ "$argo_choice" == "y" || "$argo_choice" == "Y" ]]; then
      reading "请输入argo固定隧道域名: " ARGO_DOMAIN
      green "你的argo固定隧道域名为: $ARGO_DOMAIN"
      reading "请输入argo固定隧道密钥（Json或Token）: " ARGO_AUTH
      green "你的argo固定隧道密钥为: $ARGO_AUTH"
  else
      green "ARGO隧道变量未设置，将使用临时隧道"
      ARGO_DOMAIN=""; ARGO_AUTH=""
      return
  fi

  generate_argo_files
}

generate_argo_files() {
  [[ -z "$ARGO_AUTH" ]] && return
  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > tunnel.json
    cat > tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ARGO_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  else
    yellow "\n当前使用的是token,请在cloudflare里设置隧道端口为${purple}${ARGO_PORT}${re}"
  fi
}


install_service () {
    purple "正在安装中,请稍等......"

    # 沿用原有 UUID / SUB_PATH，除非用户在本次运行中显式修改过
    UUID="${UUID:-${OLD_UUID:-$(uuidgen -r)}}"
    SUB_PATH="${SUB_PATH:-${OLD_SUB_PATH:-${UUID:0:8}}}"

    devil www del ${USERNAME}.${CURRENT_DOMAIN} > /dev/null 2>&1
    rm -rf $HOME/domains/${USERNAME}.${CURRENT_DOMAIN} > /dev/null 2>&1
    devil www add ${USERNAME}.${CURRENT_DOMAIN} nodejs /usr/local/bin/node24 > /dev/null 2>&1
    [ -d "$WORKDIR" ] || mkdir -p "$WORKDIR"
    $COMMAND "${WORKDIR}/app.js" "https://raw.githubusercontent.com/sk684437/sbx-native/refs/heads/serv00/ct8/nodejs/index.js" > /dev/null 2>&1
    $COMMAND "${WORKDIR}/public/index.html" "https://raw.githubusercontent.com/sk684437/nodejs-argo/refs/heads/main/index.html" > /dev/null 2>&1
    cat > ${WORKDIR}/.env <<EOF
UUID=${UUID}
SUB_PATH=${SUB_PATH}
ARGO_PORT=${ARGO_PORT}
TUIC_PORT=${TUIC_PORT}
HY2_PORT=${HY2_PORT}
${NEZHA_SERVER:+NEZHA_SERVER=$NEZHA_SERVER}
${NEZHA_PORT:+NEZHA_PORT=$NEZHA_PORT}
${NEZHA_KEY:+NEZHA_KEY=$NEZHA_KEY}
${tg_chat_id:+TG_CHAT_ID=$tg_chat_id}
${tg_token:+TG_TOKEN=$tg_token}
${ARGO_DOMAIN:+ARGO_DOMAIN=$ARGO_DOMAIN}
${ARGO_AUTH:+ARGO_AUTH=$([[ -z "$ARGO_AUTH" ]] && echo "" || ([[ "$ARGO_AUTH" =~ ^\{.* ]] && echo "'$ARGO_AUTH'" || echo "$ARGO_AUTH"))}
EOF

  ln -fs /usr/local/bin/node24 ~/bin/node > /dev/null 2>&1
  ln -fs /usr/local/bin/npm24 ~/bin/npm > /dev/null 2>&1
  mkdir -p ~/.npm-global
  npm config set prefix '~/.npm-global'
  echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile && source $HOME/.bash_profile
  rm -rf $HOME/.npmrc > /dev/null 2>&1
  cd ${WORKDIR} && npm install dotenv axios koffi --silent > /dev/null 2>&1
  devil www restart ${USERNAME}.${CURRENT_DOMAIN} > /dev/null 2>&1
  yellow "服务启动中...."
  sleep 3
  if curl -o /dev/null -m 3 -s -w "%{http_code}" https://${USERNAME}.${CURRENT_DOMAIN} | grep -q "200"; then
      green "服务已启动成功,请先访问 https://${USERNAME}.${CURRENT_DOMAIN}  启动服务，过20秒再访问订阅获取节点"
  else
      red "服务启动失败，请检查端口是否被占用或配置是否正确"
  fi

  TOKEN=$(sed -n 's/^SUB_PATH=\(.*\)/\1/p' $HOME/domains/${USERNAME}.${CURRENT_DOMAIN}/public_nodejs/.env)
  green "\n订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/${TOKEN}\n节点订阅链接适用于V2rayN/Nekoray/ShadowRocket/karing/Loon/sterisand 等\n"

}

quick_command() {
  COMMAND="00"
  SCRIPT_PATH="$HOME/bin/$COMMAND"
  mkdir -p "$HOME/bin"
  set +H
  printf '#!/bin/bash\n' > "$SCRIPT_PATH"
  echo "bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_serv00.sh)" >> "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null
      source "$HOME/.bashrc"
  fi
  green "快捷指令00创建成功,下次运行输入00快速进入菜单\n"
}

show_nodes(){
cat ${WORKDIR}/.npm/sub.txt
TOKEN=$(sed -n 's/^SUB_PATH=\(.*\)/\1/p' $HOME/domains/${USERNAME}.${CURRENT_DOMAIN}/public_nodejs/.env)
yellow "\n订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/${TOKEN}\n节点订阅链接适用于V2rayN/Nekoray/ShadowRocket/karing/Loon/sterisand 等\n"
}

menu() {
  clear
  echo ""
  purple "=== Serv00|Ct8|HostUNO 老王sing-box三合一安装脚本 ===\n"
  echo -e "${green}Youtube频道：${re}${yellow}https://youtube.com/@eooce${re}\n"
  echo -e "${green}TG反馈群组：${re}${yellow}https://t.me/eooceu${re}\n"
  purple "转载请著名出处，请勿滥用\n"
  yellow "快速启动命令00\n"
  green "1. 安装"
  echo  "==============="
  red "2. 卸载"
  echo  "==============="
  green "3. 查看节点信息"
  echo  "==============="
  yellow "4. 初始化系统"
  echo  "==============="
  red "0. 退出脚本"
  echo "==========="
  reading "请输入选择(0-5): " choice
  echo ""
  case "${choice}" in
      1) install_singbox;;
      2) uninstall_singbox;; 
      3) show_nodes ;; 
      4) reset_system ;;
      0) exit 0 ;;
      *) red "无效的选项，请输入 0 到 5" ;;
  esac
}
menu
