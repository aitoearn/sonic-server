#!/bin/bash
set -e

# 配置
SERVER_IP=""  # 填写腾讯服务器 IP
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="/root/sonic-server-deploy"

echo "========================================="
echo "  Sonic Server 部署脚本（服务器构建）"
echo "========================================="
echo ""

# 如果 SERVER_IP 为空，提示输入
if [ -z "$SERVER_IP" ]; then
    read -p "请输入腾讯服务器 IP: " SERVER_IP
fi

echo "服务器 IP: $SERVER_IP"
echo "项目目录：$PROJECT_DIR"
echo ""

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "错误：Docker 未运行，请先启动 Docker"
    exit 1
fi

# 检查 Maven 是否安装
if ! command -v mvn &> /dev/null; then
    echo "警告：本地未安装 Maven，将在服务器上构建"
fi

echo ""
echo "步骤 1/4: 打包项目..."

# 打包项目（排除 target 和 node_modules）
cd "$PROJECT_DIR"
tar --exclude='target' \
    --exclude='*.iml' \
    --exclude='.idea' \
    --exclude='.git' \
    --exclude='*.log' \
    -czf /tmp/sonic-server-src.tar.gz .

echo "项目已打包：/tmp/sonic-server-src.tar.gz"

echo ""
echo "步骤 2/4: 上传到腾讯服务器..."

# 上传
scp /tmp/sonic-server-src.tar.gz root@$SERVER_IP:$DEPLOY_DIR/

echo "项目已上传到：$DEPLOY_DIR"

echo ""
echo "步骤 3/4: 在服务器上构建和部署..."

# 在服务器上执行
ssh root@$SERVER_IP << 'ENDSSH'
set -e

DEPLOY_DIR="/root/sonic-server-deploy"
SONIC_DIR="$DEPLOY_DIR/sonic-server"
RUN_DIR="$DEPLOY_DIR/sonic-server-v2.7.2"

cd $DEPLOY_DIR

echo ""
echo "===== 解压源码 ====="
tar -xzf sonic-server-src.tar.gz

echo "===== 进入项目目录 ====="
cd $SONIC_DIR

echo "===== 检查 Docker ====="
if ! command -v docker &> /dev/null; then
    echo "错误：服务器未安装 Docker"
    exit 1
fi

echo "===== 检查 Maven ====="
if ! command -v mvn &> /dev/null; then
    echo "错误：服务器未安装 Maven"
    exit 1
fi

echo "===== 编译项目 ====="
mvn clean package -DskipTests -q

echo "===== 构建 Docker 镜像 ====="
echo "正在构建 eureka..."
docker build -t sonic-server-eureka:dev -f sonic-server-eureka/src/main/docker/Dockerfile . > /dev/null

echo "正在构建 gateway..."
docker build -t sonic-server-gateway:dev -f sonic-server-gateway/src/main/docker/Dockerfile . > /dev/null

echo "正在构建 controller..."
docker build -t sonic-server-controller:dev -f sonic-server-controller/src/main/docker/Dockerfile . > /dev/null

echo "正在构建 folder..."
docker build -t sonic-server-folder:dev -f sonic-server-folder/src/main/docker/Dockerfile . > /dev/null

echo "===== 镜像构建完成 ====="
docker images | grep sonic-server

echo ""
echo "===== 更新运行环境配置 ====="
cd $RUN_DIR

# 备份原有配置
if [ -f docker-compose.yml ]; then
    cp docker-compose.yml docker-compose.yml.bak
fi

# 更新 docker-compose.yml 使用本地镜像
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  sonic-mysql:
    image: mysql:8.0
    container_name: sonic-mysql
    environment:
      MYSQL_ROOT_PASSWORD: nuaa322
      MYSQL_DATABASE: sonic
      TZ: Asia/Shanghai
    volumes:
      - ./mysql-data:/var/lib/mysql
      - ./mysql-conf:/etc/mysql/conf.d
    networks:
      - sonic-network
    restart: always

  sonic-server-eureka:
    image: "sonic-server-eureka:dev"
    hostname: sonic-server-eureka
    environment:
      - SONIC_EUREKA_USERNAME=sonic
      - SONIC_EUREKA_PASSWORD=sonic
      - SONIC_EUREKA_PORT=8761
      - SONIC_EUREKA_HOST=sonic-server-eureka
    volumes:
      - ./logs/:/logs/
    ports:
      - "8761:8761"
    networks:
      - sonic-network
    depends_on:
      - sonic-mysql
    restart: on-failure

  sonic-server-gateway:
    image: "sonic-server-gateway:dev"
    hostname: sonic-server-gateway
    environment:
      - SONIC_EUREKA_USERNAME=sonic
      - SONIC_EUREKA_PASSWORD=sonic
      - SONIC_EUREKA_PORT=8761
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - SECRET_KEY=sonic-secret-key-change-this-in-production
      - EXPIRE_DAY=7
    volumes:
      - ./logs/:/logs/
    depends_on:
      - sonic-server-eureka
    networks:
      - sonic-network
    restart: on-failure

  sonic-server-controller:
    image: "sonic-server-controller:dev"
    environment:
      - SONIC_EUREKA_USERNAME=sonic
      - SONIC_EUREKA_PASSWORD=sonic
      - SONIC_EUREKA_PORT=8761
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - MYSQL_HOST=sonic-mysql
      - MYSQL_PORT=3306
      - MYSQL_DATABASE=sonic
      - MYSQL_USERNAME=root
      - MYSQL_PASSWORD=nuaa322
      - SONIC_SERVER_HOST=0.0.0.0
      - SONIC_SERVER_PORT=3000
      - SECRET_KEY=sonic-secret-key-change-this-in-production
      - EXPIRE_DAY=7
      - REGISTER_ENABLE=true
      - NORMAL_USER_ENABLE=true
      - LDAP_USER_ENABLE=false
      - LDAP_USER_ID=uid
      - LDAP_BASE_DN=ou=users
      - LDAP_BASE=ou=system
      - LDAP_USERNAME=uid=admin,ou=system
      - LDAP_PASSWORD=sonic
      - LDAP_URL=ldap://localhost:10389
      - LDAP_OBJECT_CLASS=person
    networks:
      - sonic-network
    volumes:
      - ./logs/:/logs/
    depends_on:
      - sonic-mysql
    restart: on-failure

  sonic-server-folder:
    image: "sonic-server-folder:dev"
    environment:
      - SONIC_EUREKA_USERNAME=sonic
      - SONIC_EUREKA_PASSWORD=sonic
      - SONIC_EUREKA_HOST=sonic-server-eureka
      - SONIC_EUREKA_PORT=8761
      - SONIC_SERVER_HOST=0.0.0.0
      - SONIC_SERVER_PORT=3000
      - SECRET_KEY=sonic-secret-key-change-this-in-production
      - EXPIRE_DAY=7
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
      - "3000:80"

networks:
  sonic-network:
    driver: bridge
EOF

echo "===== 重启服务 ====="
docker-compose down > /dev/null 2>&1 || true
docker-compose up -d

echo ""
echo "===== 等待服务启动 ====="
sleep 15

echo ""
echo "===== 服务状态 ====="
docker-compose ps

echo ""
echo "===== 最近的日志 ====="
docker-compose logs --tail=5

echo ""
echo "========================================="
echo "  部署完成！"
echo "========================================="
echo ""
echo "访问地址：http://$SERVER_IP:3000"
echo "Eureka:   http://$SERVER_IP:8761"
echo ""
echo "管理命令:"
echo "  查看日志：cd $RUN_DIR && docker-compose logs -f"
echo "  -f 停止服务：cd $RUN_DIR && docker-compose down"
echo "  重启服务：cd $RUN_DIR && docker-compose restart"
echo ""
ENDSSH

# 清理临时文件
rm -f /tmp/sonic-server-src.tar.gz

echo ""
echo "========================================="
echo "  部署脚本执行完成！"
echo "========================================="
echo ""
echo "请在服务器上查看部署结果"
echo "访问地址：http://$SERVER_IP:3000"
