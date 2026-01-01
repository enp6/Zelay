#!/bin/bash

# Zelay Agent 一键部署脚本
# 用法：
#   安装（交互模式）: ./zelay_agent.sh
#   安装（非交互模式）: ./zelay_agent.sh server=1.1.1.1:13001 apikey=YOUR_KEY dns=223.5.5.5:53,119.29.29.29:53
#   更新: ./zelay_agent.sh update
#   卸载: ./zelay_agent.sh uninstall

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
INSTALL_DIR="/etc/zelay"
BINARY_URL="https://raw.githubusercontent.com/enp6/Zelay/main/zelay"
SERVICE_NAME="zelay-agent"
DEFAULT_DNS="223.5.5.5:53,119.29.29.29:53"

# 参数变量
SERVER_ADDR=""
API_KEY=""
DNS_SERVERS=""

# 日志函数
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
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Zelay Agent 部署脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}用法：${NC}"
    echo -e "  ${YELLOW}安装（交互模式）：${NC}"
    echo -e "    $0"
    echo ""
    echo -e "  ${YELLOW}安装（非交互模式）：${NC}"
    echo -e "    $0 server=IP:PORT apikey=YOUR_KEY [dns=DNS1:PORT,DNS2:PORT]"
    echo ""
    echo -e "  ${YELLOW}更新程序：${NC}"
    echo -e "    $0 update"
    echo ""
    echo -e "  ${YELLOW}卸载：${NC}"
    echo -e "    $0 uninstall"
    echo ""
    echo -e "${BLUE}示例：${NC}"
    echo -e "  $0 server=103.73.220.3:13001 apikey=abc123xyz"
    echo -e "  $0 update"
    echo -e "  $0 uninstall"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo ""
    exit 0
}

# 检查root权限
check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0 $*"
        exit 1
    fi
}

# 解析命令行参数
parse_args() {
    for arg in "$@"; do
        case $arg in
            server=*)
                SERVER_ADDR="${arg#*=}"
                ;;
            apikey=*)
                API_KEY="${arg#*=}"
                ;;
            dns=*)
                DNS_SERVERS="${arg#*=}"
                ;;
            *)
                log_warning "未知参数: $arg"
                ;;
        esac
    done
}

# 交互式输入
interactive_input() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Zelay Agent 部署脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # 输入服务器地址
    if [ -z "$SERVER_ADDR" ]; then
        read -p "请输入服务器地址 (格式: IP:PORT): " SERVER_ADDR
        while [ -z "$SERVER_ADDR" ]; do
            log_error "服务器地址不能为空"
            read -p "请输入服务器地址 (格式: IP:PORT): " SERVER_ADDR
        done
    fi

    # 输入API Key
    if [ -z "$API_KEY" ]; then
        read -p "请输入API Key: " API_KEY
        while [ -z "$API_KEY" ]; do
            log_error "API Key不能为空"
            read -p "请输入API Key: " API_KEY
        done
    fi

    # 输入DNS服务器（可选）
    if [ -z "$DNS_SERVERS" ]; then
        read -p "请输入DNS服务器 (默认: $DEFAULT_DNS, 多个用逗号分隔): " DNS_SERVERS
        if [ -z "$DNS_SERVERS" ]; then
            DNS_SERVERS="$DEFAULT_DNS"
        fi
    fi

    echo ""
    log_info "配置信息："
    log_info "  服务器地址: $SERVER_ADDR"
    log_info "  API Key: ${API_KEY:0:10}..."
    log_info "  DNS服务器: $DNS_SERVERS"
    echo ""
    read -p "确认以上配置正确？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_warning "用户取消安装"
        exit 0
    fi
}

# 安装依赖
install_dependencies() {
    log_info "检查并安装依赖..."
    
    if command -v apt-get > /dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y wget curl systemd
    elif command -v yum > /dev/null 2>&1; then
        yum install -y wget curl systemd
    elif command -v dnf > /dev/null 2>&1; then
        dnf install -y wget curl systemd
    else
        log_warning "未知的包管理器，请手动安装 wget curl systemd"
    fi
    
    log_success "依赖检查完成"
}

# 创建安装目录
create_directories() {
    log_info "创建安装目录..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/instances"
    
    log_success "目录创建完成: $INSTALL_DIR"
}

# 下载Zelay二进制文件
download_binary() {
    log_info "下载Zelay程序..."
    
    local tmp_file="/tmp/zelay_download"
    
    if wget -q --show-progress -O "$tmp_file" "$BINARY_URL"; then
        mv "$tmp_file" "$INSTALL_DIR/zelay"
        chmod +x "$INSTALL_DIR/zelay"
        log_success "程序下载完成"
    else
        log_error "下载失败，请检查网络连接或URL是否正确"
        log_info "下载地址: $BINARY_URL"
        exit 1
    fi
    
    # 验证二进制文件
    if ! "$INSTALL_DIR/zelay" --version > /dev/null 2>&1 && ! "$INSTALL_DIR/zelay" --help > /dev/null 2>&1; then
        log_warning "无法验证程序版本，但文件已下载"
    fi
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    # 将DNS_SERVERS转换为JSON数组格式
    IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
    DNS_JSON=""
    for dns in "${DNS_ARRAY[@]}"; do
        dns=$(echo "$dns" | xargs)
        if [ -n "$DNS_JSON" ]; then
            DNS_JSON="$DNS_JSON, "
        fi
        DNS_JSON="${DNS_JSON}\"$dns\""
    done
    
    cat > "$INSTALL_DIR/zelay.conf" << CONFEOF
{
  "dns": {
    "mode": "ipv4_then_ipv6",
    "nameservers": [$DNS_JSON],
    "timeout": 5,
    "cache_size": 256
  },
  "network": {
    "tcp_keepalive": 60,
    "tcp_timeout": 10,
    "udp_timeout": 30,
    "send_proxy": false,
    "accept_proxy": false,
    "no_tcp": false,
    "use_udp": true
  },
  "endpoints": []
}
CONFEOF
    
    log_success "配置文件已生成: $INSTALL_DIR/zelay.conf"
}

# 创建systemd服务
create_service() {
    log_info "创建systemd服务..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << SERVICEEOF
[Unit]
Description=Zelay Agent
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/zelay api -c $INSTALL_DIR/zelay.conf --server "$SERVER_ADDR" --key "$API_KEY"
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=23

# 资源限制优化
LimitNOFILE=1048576
LimitNPROC=1048576

# 日志管理
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF
    
    systemctl daemon-reload
    log_success "systemd服务已创建: ${SERVICE_NAME}.service"
}

# 启动服务
start_service() {
    log_info "启动Zelay Agent服务..."
    
    systemctl enable "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"
    
    sleep 2
    
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log_success "服务启动成功！"
    else
        log_error "服务启动失败，请查看日志"
        log_info "查看日志: journalctl -u ${SERVICE_NAME}.service -f"
        exit 1
    fi
}

# 显示安装信息
show_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Zelay Agent 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}安装信息：${NC}"
    echo -e "  安装目录: ${YELLOW}$INSTALL_DIR${NC}"
    echo -e "  配置文件: ${YELLOW}$INSTALL_DIR/zelay.conf${NC}"
    echo -e "  服务名称: ${YELLOW}${SERVICE_NAME}.service${NC}"
    echo ""
    echo -e "${BLUE}常用命令：${NC}"
    echo -e "  启动服务: ${YELLOW}systemctl start ${SERVICE_NAME}${NC}"
    echo -e "  停止服务: ${YELLOW}systemctl stop ${SERVICE_NAME}${NC}"
    echo -e "  重启服务: ${YELLOW}systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  查看状态: ${YELLOW}systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  查看日志: ${YELLOW}journalctl -u ${SERVICE_NAME} -f${NC}"
    echo ""
    echo -e "${BLUE}文件位置：${NC}"
    echo -e "  实例数据: ${YELLOW}$INSTALL_DIR/instances/${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# 卸载功能
uninstall() {
    log_warning "开始卸载Zelay Agent..."
    
    # 停止服务
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        systemctl stop "${SERVICE_NAME}.service"
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet "${SERVICE_NAME}.service" 2>/dev/null; then
        systemctl disable "${SERVICE_NAME}.service"
    fi
    
    # 删除服务文件
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    
    # 询问是否删除配置和数据
    read -p "是否删除配置文件和实例数据？(y/n): " delete_data
    if [ "$delete_data" = "y" ] || [ "$delete_data" = "Y" ]; then
        rm -rf "$INSTALL_DIR"
        log_success "配置文件和数据已删除"
    else
        log_info "保留配置文件和数据: $INSTALL_DIR"
    fi
    
    log_success "卸载完成！"
    exit 0
}

# 更新功能
update() {
    log_info "开始更新Zelay Agent..."
    
    # 检查是否已安装
    if [ ! -f "$INSTALL_DIR/zelay" ]; then
        log_error "未找到Zelay程序，请先运行安装"
        log_info "安装命令: $0"
        exit 1
    fi
    
    # 备份当前版本
    log_info "备份当前版本..."
    local backup_file="$INSTALL_DIR/zelay.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$INSTALL_DIR/zelay" "$backup_file"
    log_success "已备份到: $backup_file"
    
    # 获取当前版本信息（如果可用）
    local old_version="未知"
    if "$INSTALL_DIR/zelay" --version > /dev/null 2>&1; then
        old_version=$("$INSTALL_DIR/zelay" --version 2>&1 | head -n1)
    fi
    log_info "当前版本: $old_version"
    
    # 停止服务
    local was_running=false
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        was_running=true
        log_info "停止服务..."
        systemctl stop "${SERVICE_NAME}.service"
    fi
    
    # 下载新版本
    log_info "下载最新版本..."
    local tmp_file="/tmp/zelay_update_$$"
    
    if wget -q --show-progress -O "$tmp_file" "$BINARY_URL"; then
        # 验证下载的文件
        if [ ! -s "$tmp_file" ]; then
            log_error "下载的文件为空"
            rm -f "$tmp_file"
            exit 1
        fi
        
        # 替换二进制文件
        mv "$tmp_file" "$INSTALL_DIR/zelay"
        chmod +x "$INSTALL_DIR/zelay"
        
        # 获取新版本信息
        local new_version="未知"
        if "$INSTALL_DIR/zelay" --version > /dev/null 2>&1; then
            new_version=$("$INSTALL_DIR/zelay" --version 2>&1 | head -n1)
        fi
        
        log_success "更新成功！"
        echo ""
        log_info "版本信息："
        log_info "  旧版本: $old_version"
        log_info "  新版本: $new_version"
        echo ""
        
    else
        log_error "下载失败，恢复备份..."
        mv "$backup_file" "$INSTALL_DIR/zelay"
        chmod +x "$INSTALL_DIR/zelay"
        log_info "已恢复到原版本"
        exit 1
    fi
    
    # 重启服务
    if [ "$was_running" = true ]; then
        log_info "重启服务..."
        systemctl start "${SERVICE_NAME}.service"
        sleep 2
        
        if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
            log_success "服务重启成功！"
        else
            log_error "服务启动失败，尝试恢复备份..."
            systemctl stop "${SERVICE_NAME}.service"
            mv "$backup_file" "$INSTALL_DIR/zelay"
            chmod +x "$INSTALL_DIR/zelay"
            systemctl start "${SERVICE_NAME}.service"
            log_warning "已恢复到原版本"
            exit 1
        fi
    fi
    
    # 显示状态
    echo ""
    log_info "查看服务状态: systemctl status ${SERVICE_NAME}"
    log_info "查看日志: journalctl -u ${SERVICE_NAME} -f"
    log_info "备份文件: $backup_file"
    echo ""
    log_success "更新完成！"
    exit 0
}

# 主函数
main() {
    # 显示帮助
    if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
    fi
    
    # 检查是否为卸载命令
    if [ "$1" = "uninstall" ] || [ "$1" = "remove" ]; then
        check_root
        uninstall
    fi
    
    # 检查是否为更新命令
    if [ "$1" = "update" ] || [ "$1" = "upgrade" ]; then
        check_root
        update
    fi
    
    check_root
    parse_args "$@"
    
    # 如果参数不完整，进入交互模式
    if [ -z "$SERVER_ADDR" ] || [ -z "$API_KEY" ]; then
        interactive_input
    else
        # 非交互模式，使用默认DNS（如果未提供）
        if [ -z "$DNS_SERVERS" ]; then
            DNS_SERVERS="$DEFAULT_DNS"
        fi
        log_info "非交互模式部署"
        log_info "服务器: $SERVER_ADDR"
        log_info "DNS: $DNS_SERVERS"
    fi
    
    install_dependencies
    create_directories
    download_binary
    generate_config
    create_service
    start_service
    show_info
}

# 捕获Ctrl+C
trap 'echo ""; log_warning "安装已取消"; exit 1' INT

# 运行主函数
main "$@"