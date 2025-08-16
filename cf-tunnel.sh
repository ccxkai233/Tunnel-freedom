#!/bin/bash
# 复用系统已安装的 cloudflared（二进制路径：/usr/bin/cloudflared）
# 不下载、不覆盖二进制；其余逻辑与原脚本一致。

set -e

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # 清除颜色

CLOUDFLARED_BIN="/usr/bin/cloudflared"
SERVICE_PATH="/etc/systemd/system/cloudflared-tunnel.service"
LOG_PATH="/var/log/cloudflared.log"

# 确认 cloudflared 是否存在且可执行
if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo -e "${RED}未检测到 ${CLOUDFLARED_BIN}${NC}"
    echo -e "${YELLOW}请先通过官方 apt 源安装：${NC}"
    echo "sudo mkdir -p --mode=0755 /usr/share/keyrings"
    echo "curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null"
    echo "echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list"
    echo "sudo apt-get update && sudo apt-get install -y cloudflared"
    exit 1
fi

echo -e "${GREEN}检测到 cloudflared：$($CLOUDFLARED_BIN --version 2>/dev/null || echo 'unknown version')${NC}"

# 检查服务是否存在
SERVICE_EXISTS=false
if sudo systemctl list-units --full --all | grep -q 'cloudflared-tunnel.service'; then
    SERVICE_EXISTS=true
    echo -e "${YELLOW}已检测到 cloudflared-tunnel systemd 服务${NC}"

    # 显示之前的本地地址与公网地址
    if [[ -f "$SERVICE_PATH" ]]; then
        OLD_ADDR=$(grep -oP '(?<=ExecStart=/usr/bin/cloudflared tunnel --url ).*' "$SERVICE_PATH" 2>/dev/null || echo "")
        if [[ -n "$OLD_ADDR" ]]; then
            echo -e "${GREEN}之前配置的本地地址：$OLD_ADDR${NC}"
        fi
    fi
    if [[ -f "$LOG_PATH" ]]; then
        OLD_DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG_PATH" 2>/dev/null | tail -n1 || echo "")
        if [[ -n "$OLD_DOMAIN" ]]; then
            echo -e "${GREEN}最近一次获取的公网地址：$OLD_DOMAIN${NC}"
        fi
    fi

    read -p "是否要卸载旧服务？(y/n): " UNINSTALL
    if [[ "$UNINSTALL" == "y" || "$UNINSTALL" == "Y" ]]; then
        echo -e "${BLUE}正在卸载旧服务...${NC}"
        sudo systemctl stop cloudflared-tunnel || true
        sudo systemctl disable cloudflared-tunnel || true
        sudo rm -f "$SERVICE_PATH"
        sudo rm -f "$LOG_PATH"
        sudo systemctl daemon-reload
        SERVICE_EXISTS=false
        echo -e "${GREEN}服务卸载完成${NC}"
    else
        echo -e "${YELLOW}将保留旧服务配置，仅修改穿透地址${NC}"
    fi
fi

# 用户选择运行模式
echo ""
echo -e "${YELLOW}请选择运行模式：${NC}"
echo "1) 临时运行（前台运行并显示临时访问域名）"
echo "2) 后台运行（自动配置后台服务并显示访问域名）"
read -p "请输入 1 或 2: " MODE

# 输入内网地址
read -p "请输入要穿透的本地地址（例如 127.0.0.1:8080）: " LOCAL_ADDR

echo -e "${YELLOW}本地地址: ${NC}$LOCAL_ADDR"
echo -e "${YELLOW}公网地址将在后续日志中检测获取...${NC}"

if [[ "$MODE" == "1" ]]; then
    echo -e "${BLUE}正在前台运行 cloudflared...${NC}"

    LOGFILE=$(mktemp)
    stdbuf -oL "$CLOUDFLARED_BIN" tunnel --url "$LOCAL_ADDR" 2>&1 | tee "$LOGFILE" &

    PID=$!
    echo -e "${YELLOW}等待 cloudflared 输出访问域名...${NC}"

    for i in {1..60}; do
        DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOGFILE" | head -n1)
        if [[ -n "$DOMAIN" ]]; then
            echo ""
            echo -e "${GREEN}成功获取公网临时访问域名：$DOMAIN${NC}"
            echo ""
            wait $PID
            exit 0
        fi
        sleep 1
    done

    echo -e "${RED}超时未能获取临时域名，日志保存在：$LOGFILE${NC}"
    kill $PID 2>/dev/null || true
    exit 1

elif [[ "$MODE" == "2" ]]; then
    echo -e "${BLUE}正在配置 systemd 服务...${NC}"

    if [[ "$SERVICE_EXISTS" == false ]]; then
        sudo bash -c "cat > $SERVICE_PATH" <<EOF
[Unit]
Description=Cloudflared Tunnel Service (TryCloudflare)
After=network.target

[Service]
ExecStart=$CLOUDFLARED_BIN tunnel --url $LOCAL_ADDR
Restart=always
StandardOutput=append:$LOG_PATH
StandardError=append:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable --now cloudflared-tunnel
    else
        echo -e "${YELLOW}更新 systemd 服务配置中的穿透地址...${NC}"
        sudo truncate -s 0 "$LOG_PATH" 2>/dev/null || sudo bash -c "> $LOG_PATH"
        sudo sed -i "s|^ExecStart=.*|ExecStart=$CLOUDFLARED_BIN tunnel --url $LOCAL_ADDR|" "$SERVICE_PATH"
        sudo systemctl daemon-reload
        sudo systemctl restart cloudflared-tunnel
    fi

    echo -e "${GREEN}服务已启动，日志保存在 $LOG_PATH${NC}"
    echo -e "${YELLOW}等待 cloudflared 输出访问域名...${NC}"

    for i in {1..30}; do
        DOMAIN=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG_PATH" | head -n1)
        if [[ -n "$DOMAIN" ]]; then
            echo ""
            echo -e "${GREEN}成功获取公网访问域名：$DOMAIN${NC}"
            echo ""
            exit 0
        fi
        sleep 1
    done

    echo -e "${RED}超时未能获取公网访问域名，请稍后手动查看：$LOG_PATH${NC}"
    exit 1

else
    echo -e "${RED}无效输入，请输入 1 或 2${NC}"
    exit 1
fi
