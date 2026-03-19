#!/bin/bash
set -e

echo "========================================="
echo "  Sonic Server 一键部署脚本"
echo "  支持：阿里云 / 腾讯云 / 华为云 ECS"
echo "========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 sudo 运行此脚本：sudo ./deploy-aliyun.sh"
    exit 1
fi

# 配置变量
DEPLOY_DIR="/opt/sonic-server"
LOG_DIR="/opt/sonic-server/logs"
KEEP_DIR="/opt/sonic-server/keepFiles"
IMAGE_DIR="/opt/sonic-server/imageFiles"
RECORD_DIR="/opt/sonic-server/recordFiles"
PACKAGE_DIR="/opt/sonic-server/packageFiles"

# 检测云平台
detect_cloud() {
    if [ -f /sys/class/dmi/id/product_version ]; then
        PRODUCT_VERSION=$(cat /sys/class/dmi/id/product_version 2>/dev/null || echo "")
        if [[ "$PRODUCT_VERSION" == *"TencentCloud"* ]] || [[ "$PRODUCT_VERSION" == *"CVM"* ]]; then
            echo "tencent"
            return
        fi
        if [[ "$PRODUCT_VERSION" == *"Alibaba Cloud"* ]] || [[ "$PRODUCT_VERSION" == *"ECS"* ]]; then
            echo "aliyun"
            return
        fi
    fi
    echo "unknown"
}

CLOUD_PROVIDER=$(detect_cloud)
log_info "检测到云服务商：$CLOUD_PROVIDER"

# 根据云平台选择 Docker 镜像源
if [ "$CLOUD_PROVIDER" == "tencent" ]; then
    DOCKER_MIRROR="https://mirrors.tencent.com/docker-ce"
    log_info "使用腾讯云 Docker 镜像源"
elif [ "$CLOUD_PROVIDER" == "aliyun" ]; then
    DOCKER_MIRROR="https://get.docker.com --mirror Aliyun"
    log_info "使用阿里云 Docker 镜像源"
else
    DOCKER_MIRROR="https://get.docker.com"
    log_info "使用官方 Docker 安装源"
fi

echo ""
log_info "步骤 1/7: 安装 Docker..."

# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    log_info "正在安装 Docker..."
    if [ "$CLOUD_PROVIDER" == "tencent" ]; then
        # 腾讯云使用官方脚本 + 国内镜像加速
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh --mirror Aliyun
    else
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    fi
    systemctl enable docker
    systemctl start docker
    log_info "Docker 安装完成"
else
    log_info "Docker 已安装，跳过"
fi

echo ""
log_info "步骤 2/7: 安装 Docker Compose..."

# 检查 Docker Compose 是否已安装
if ! command -v docker-compose &> /dev/null; then
    log_info "正在安装 Docker Compose..."
    curl -L https://github.com/docker/compose/releases/download/v2.24.1/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    log_info "Docker Compose 安装完成"
else
    log_info "Docker Compose 已安装，跳过"
fi

echo ""
log_info "步骤 3/7: 创建部署目录..."

# 创建目录结构
mkdir -p $DEPLOY_DIR
mkdir -p $LOG_DIR
mkdir -p $KEEP_DIR
mkdir -p $IMAGE_DIR
mkdir -p $RECORD_DIR
mkdir -p $PACKAGE_DIR

log_info "目录创建完成：$DEPLOY_DIR"

echo ""
log_info "步骤 4/7: 生成配置文件..."

# 生成 .env 文件
cat > $DEPLOY_DIR/.env << 'EOF'
##################
# Service Config #
##################
SONIC_SERVER_HOST=0.0.0.0
SONIC_SERVER_PORT=3000
SONIC_EUREKA_USERNAME=sonic
SONIC_EUREKA_PASSWORD=sonic
SONIC_EUREKA_PORT=8761

################
# MySQL Config #
################
# 如果使用阿里云 RDS，请替换为 RDS 内网连接地址
# 如果在本地运行 MySQL，请改为 mysql 或 127.0.0.1
MYSQL_HOST=172.17.0.1
MYSQL_PORT=3306
MYSQL_DATABASE=sonic
MYSQL_USERNAME=root
MYSQL_PASSWORD=Sonic!@#123

################
# User Config  #
################
REGISTER_ENABLE=true
NORMAL_USER_ENABLE=true
LDAP_USER_ENABLE=false
SECRET_KEY=sonic-secret-key-change-this-in-production
EXPIRE_DAY=7

################
# LDAP Config  #
################
LDAP_USER_ID=uid
LDAP_BASE_DN=ou=users
LDAP_BASE=ou=system
LDAP_USERNAME=uid=admin,ou=system
LDAP_PASSWORD=sonic
LDAP_URL=ldap://localhost:10389
LDAP_OBJECT_CLASS=person
EOF

log_info "配置文件已生成：$DEPLOY_DIR/.env"
log_warn "请编辑 $DEPLOY_DIR/.env 修改数据库密码和 SECRET_KEY"

echo ""
log_info "步骤 5/7: 下载 docker-compose 配置文件..."

# 创建 docker-compose.yml
cat > $DEPLOY_DIR/docker-compose.yml << 'EOF'
version: '3'
services:
  sonic-server-eureka:
    image: "sonicorg/sonic-server-eureka:2.0.0"
    hostname: sonic-server-eureka
    environment:
      - SONIC_EUREKA_USERNAME
      - SONIC_EUREKA_PASSWORD
      - SONIC_EUREKA_PORT
      - SONIC_EUREKA_HOST=sonic-server-eureka
    volumes:
      - ./logs/:/logs/
    networks:
      - sonic-network
    ports:
      - "${SONIC_EUREKA_PORT}:${SONIC_EUREKA_PORT}"
    restart: on-failure

  sonic-server-gateway:
    image: "sonicorg/sonic-server-gateway:2.0.0"
    hostname: sonic-server-gateway
    environment:
      - SONIC_EUREKA_USERNAME
      - SONIC_EUREKA_PASSWORD
      - SONIC_EUREKA_PORT
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - SECRET_KEY
      - EXPIRE_DAY
    volumes:
      - ./logs/:/logs/
    depends_on:
      - sonic-server-eureka
    networks:
      - sonic-network
    restart: on-failure

  sonic-server-controller:
    image: "sonicorg/sonic-server-controller:2.0.0"
    environment:
      - SONIC_EUREKA_USERNAME
      - SONIC_EUREKA_PASSWORD
      - SONIC_EUREKA_PORT
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - MYSQL_HOST
      - MYSQL_PORT
      - MYSQL_DATABASE
      - MYSQL_USERNAME
      - MYSQL_PASSWORD
      - SONIC_SERVER_HOST
      - SONIC_SERVER_PORT
      - SECRET_KEY
      - EXPIRE_DAY
      - REGISTER_ENABLE
      - NORMAL_USER_ENABLE
      - LDAP_USER_ENABLE
      - LDAP_USER_ID
      - LDAP_BASE_DN
      - LDAP_BASE
      - LDAP_USERNAME
      - LDAP_PASSWORD
      - LDAP_URL
      - LDAP_OBJECT_CLASS
    networks:
      - sonic-network
    volumes:
      - ./logs/:/logs/
    depends_on:
      - sonic-server-eureka
    restart: on-failure

  sonic-server-folder:
    image: "sonicorg/sonic-server-folder:2.0.0"
    environment:
      - SONIC_EUREKA_USERNAME
      - SONIC_EUREKA_PASSWORD
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - SONIC_EUREKA_PORT
      - SONIC_SERVER_HOST
      - SONIC_SERVER_PORT
      - SECRET_KEY
      - EXPIRE_DAY
    networks:
      - sonic-network
    volumes:
      - ./keepFiles/:/keepFiles/
      - ./imageFiles/:/imageFiles/
      - ./recordFiles/:/recordFiles/
      - ./packageFiles/:/packageFiles/
      - ./logs/:/logs/
    depends_on:
      - sonic-server-eureka
    restart: on-failure

  sonic-client-web:
    image: "sonicorg/sonic-client-web:2.0.0"
    networks:
      - sonic-network
    depends_on:
      - sonic-server-gateway
    restart: on-failure
    ports:
      - "${SONIC_SERVER_PORT}:80"

networks:
  sonic-network:
    driver: bridge
EOF

log_info "docker-compose.yml 创建完成"

echo ""
log_info "步骤 6/7: 拉取镜像并启动服务..."

cd $DEPLOY_DIR

# 拉取镜像
log_info "正在拉取 Docker 镜像..."
docker-compose pull

# 启动服务
log_info "正在启动 Sonic Server 服务..."
docker-compose up -d

echo ""
echo "========================================="
log_info "部署完成！"
echo "========================================="
echo ""
echo "服务访问地址:"
echo "  - Web 界面：http://<服务器IP>:3000"
echo "  - Eureka:   http://<服务器IP>:8761"
echo ""
echo "管理命令:"
echo "  - 查看日志：cd $DEPLOY_DIR && docker-compose logs -f"
echo "  - 停止服务：cd $DEPLOY_DIR && docker-compose down"
echo "  - 重启服务：cd $DEPLOY_DIR && docker-compose restart"
echo "  - 更新服务：cd $DEPLOY_DIR && docker-compose pull && docker-compose up -d"
echo ""
echo "配置文件位置：$DEPLOY_DIR/.env"
echo ""
log_warn "重要提示："
log_warn "1. 请确保 MySQL 数据库已创建并可访问"
log_warn "2. 请修改 .env 中的 MYSQL_PASSWORD 和 SECRET_KEY"
log_warn "3. 请在云服务商安全组开放端口：3000, 8761"
echo ""
echo "腾讯云安全组配置路径:"
echo "  控制台 > 云服务器 > 网络安全 > 安全组 > 添加入站规则"
echo "  - 端口 3000 (Web 应用)"
echo "  - 端口 8761 (Eureka)"
echo "  - 端口 3306 (MySQL, 如本地运行)"
echo ""
