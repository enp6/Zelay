#!/bin/bash

# Zelay Manager 一键部署脚本
# 支持安装、更新、卸载

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_WEB_PORT=3000
DEFAULT_AGENT_PORT=3001
INSTALL_DIR="/etc/zelay-manager"
BINARY_NAME="zelay-manager"
SERVICE_NAME="zelay-manager"
DOWNLOAD_URL="https://raw.githubusercontent.com/enp6/Zelay/main/zelay-manager"

# 解析参数
WEB_PORT=$DEFAULT_WEB_PORT
AGENT_PORT=$DEFAULT_AGENT_PORT
ACTION="install"
DATA_DIR=""

for arg in "$@"; do
    case $arg in
        webport=*|web-port=*)
            WEB_PORT="${arg#*=}"
            ;;
        agentport=*|agent-port=*)
            AGENT_PORT="${arg#*=}"
            ;;
        datadir=*|data-dir=*)
            DATA_DIR="${arg#*=}"
            ;;
        --uninstall)
            ACTION="uninstall"
            ;;
        --update)
            ACTION="update"
            ;;
        --help|-h)
            ACTION="help"
            ;;
        *)
            echo -e "${RED}未知参数: $arg${NC}"
            ACTION="help"
            ;;
    esac
done

# 设置默认数据目录
if [[ -z "$DATA_DIR" ]]; then
    DATA_DIR="${INSTALL_DIR}/data"
fi

# 打印日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
${GREEN}Zelay Manager 部署脚本${NC}

${BLUE}用法:${NC}
    bash zelay_manager.sh [选项]

${BLUE}选项:${NC}
    webport=PORT         设置 Web 管理面板端口 (默认: 3000)
    agentport=PORT       设置 Agent 连接端口 (默认: 3001)
    datadir=PATH         设置数据目录 (默认: /etc/zelay-manager/data)
    --update             更新 Zelay Manager
    --uninstall          卸载 Zelay Manager
    --help, -h           显示帮助信息

${BLUE}示例:${NC}
    # 默认安装
    bash zelay_manager.sh

    # 自定义端口安装
    bash zelay_manager.sh webport=8080 agentport=9000

    # 自定义数据目录
    bash zelay_manager.sh webport=3000 agentport=3001 datadir=/data/zelay

    # 更新
    bash zelay_manager.sh --update

    # 卸载
    bash zelay_manager.sh --uninstall

${BLUE}更多信息:${NC}
    项目地址: https://github.com/enp6/Zelay
EOF
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检查系统架构
check_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            log_info "检测到系统架构: x86_64"
            ;;
        aarch64|arm64)
            log_info "检测到系统架构: ARM64"
            ;;
        *)
            log_error "不支持的系统架构: $ARCH"
            exit 1
            ;;
    esac
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        log_info "检测到操作系统: $PRETTY_NAME"
    else
        log_error "无法识别操作系统"
        exit 1
    fi
}

# 检查端口是否被占用
check_port() {
    local port=$1
    if ss -tuln | grep -q ":${port} "; then
        log_warning "端口 $port 已被占用"
        read -p "是否继续? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
    fi
}

# 停止服务
stop_service() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "停止 $SERVICE_NAME 服务..."
        systemctl stop $SERVICE_NAME
        log_success "服务已停止"
    fi
}

# 创建安装目录
create_directory() {
    log_info "创建安装目录: $INSTALL_DIR"
    mkdir -p $INSTALL_DIR
    log_success "目录创建成功"
}

# 下载程序
download_binary() {
    log_info "下载 Zelay Manager..."
    
    # 检查是否安装了 curl 或 wget
    if command -v curl &> /dev/null; then
        curl -fsSL -o "${INSTALL_DIR}/${BINARY_NAME}" "$DOWNLOAD_URL"
    elif command -v wget &> /dev/null; then
        wget -q -O "${INSTALL_DIR}/${BINARY_NAME}" "$DOWNLOAD_URL"
    else
        log_error "未找到 curl 或 wget，请先安装"
        exit 1
    fi
    
    if [[ ! -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        log_error "下载失败"
        exit 1
    fi
    
    # 添加执行权限
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    log_success "下载完成"
}

# 设置文件权限
set_permissions() {
    log_info "设置文件权限..."
    
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    
    # 创建数据目录
    mkdir -p "$DATA_DIR"
    
    log_success "权限设置完成"
}

# 创建 systemd 服务
create_service() {
    log_info "创建 systemd 服务..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Zelay Manager
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --webport ${WEB_PORT} --agentport ${AGENT_PORT} --data-dir ${DATA_DIR}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# 资源限制
LimitNOFILE=1048576
LimitNPROC=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload
    log_success "服务创建成功"
}

# 启动服务
start_service() {
    log_info "启动 $SERVICE_NAME 服务..."
    
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    # 等待服务启动
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败，请查看日志: journalctl -u $SERVICE_NAME -n 50"
        exit 1
    fi
}

# 显示安装信息
show_install_info() {
    local SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
    
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Zelay Manager 安装成功！                      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}📦 安装目录:${NC} $INSTALL_DIR"
    echo -e "${BLUE}💾 数据目录:${NC} $DATA_DIR"
    echo -e "${BLUE}🌐 访问地址:${NC} http://${SERVER_IP}:${WEB_PORT}"
    echo -e "${BLUE}🔗 Agent 端口:${NC} ${AGENT_PORT}"
    echo
    echo -e "${YELLOW}📝 下一步操作:${NC}"
    echo -e "  1. 访问管理面板: ${BLUE}http://${SERVER_IP}:${WEB_PORT}${NC}"
    echo -e "  2. 创建管理员账号"
    echo -e "  3. 登录并开始使用"
    echo
    echo -e "${YELLOW}🛠️  常用命令:${NC}"
    echo -e "  查看状态: ${GREEN}systemctl status $SERVICE_NAME${NC}"
    echo -e "  启动服务: ${GREEN}systemctl start $SERVICE_NAME${NC}"
    echo -e "  停止服务: ${GREEN}systemctl stop $SERVICE_NAME${NC}"
    echo -e "  重启服务: ${GREEN}systemctl restart $SERVICE_NAME${NC}"
    echo -e "  查看日志: ${GREEN}journalctl -u $SERVICE_NAME -f${NC}"
    echo
    echo -e "${YELLOW}📚 更多信息:${NC}"
    echo -e "  GitHub: ${BLUE}https://github.com/enp6/Zelay${NC}"
    echo
}

# 安装函数
install() {
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              开始安装 Zelay Manager                            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    check_os
    check_architecture
    
    log_info "配置信息:"
    echo -e "  Web 端口: ${GREEN}${WEB_PORT}${NC}"
    echo -e "  Agent 端口: ${GREEN}${AGENT_PORT}${NC}"
    echo -e "  安装目录: ${GREEN}${INSTALL_DIR}${NC}"
    echo -e "  数据目录: ${GREEN}${DATA_DIR}${NC}"
    echo
    
    # 检查端口
    check_port $WEB_PORT
    check_port $AGENT_PORT
    
    # 如果已安装，先停止服务
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        log_warning "检测到已安装 Zelay Manager"
        stop_service
    fi
    
    create_directory
    download_binary
    set_permissions
    create_service
    start_service
    show_install_info
}

# 更新函数
update() {
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              开始更新 Zelay Manager                            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    
    # 检查是否已安装
    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        log_error "未检测到已安装的 Zelay Manager"
        log_info "请使用安装命令进行安装"
        exit 1
    fi
    
    # 备份当前版本
    log_info "备份当前版本..."
    if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        cp "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}.bak"
        log_success "备份完成"
    fi
    
    # 停止服务
    stop_service
    
    # 下载新版本
    download_binary
    
    # 启动服务
    start_service
    
    echo
    log_success "更新完成！"
    echo
    log_info "如果遇到问题，可以回滚到之前的版本:"
    echo -e "  ${GREEN}mv ${INSTALL_DIR}/${BINARY_NAME}.bak ${INSTALL_DIR}/${BINARY_NAME}${NC}"
    echo -e "  ${GREEN}systemctl restart $SERVICE_NAME${NC}"
    echo
}

# 卸载函数
uninstall() {
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║              开始卸载 Zelay Manager                            ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_root
    
    # 确认卸载
    log_warning "此操作将删除 Zelay Manager 及所有数据"
    read -p "确认卸载? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "卸载已取消"
        exit 0
    fi
    
    # 停止并禁用服务
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        log_info "停止并禁用服务..."
        systemctl stop $SERVICE_NAME 2>/dev/null || true
        systemctl disable $SERVICE_NAME 2>/dev/null || true
        log_success "服务已停止"
    fi
    
    # 删除服务文件
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        log_info "删除服务文件..."
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
        log_success "服务文件已删除"
    fi
    
    # 删除安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
        log_info "删除安装目录..."
        rm -rf "$INSTALL_DIR"
        log_success "安装目录已删除"
    fi
    
    echo
    log_success "Zelay Manager 已完全卸载！"
    echo
    log_info "感谢使用 Zelay Manager"
    echo
}

# 主函数
main() {
    case $ACTION in
        install)
            install
            ;;
        update)
            update
            ;;
        uninstall)
            uninstall
            ;;
        help)
            show_help
            ;;
        *)
            log_error "未知操作: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main