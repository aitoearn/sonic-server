# Sonic Server 云部署指南

本文档介绍如何将 Sonic Server 部署到云服务器（阿里云/腾讯云/华为云）。

## 前置准备

### 1. 云资源准备

#### 方案 A：使用云数据库（推荐）
**阿里云 RDS / 腾讯云 CDB / 华为云 RDS**
1. 登录云控制台
2. 创建 MySQL 实例（建议 5.7+ 版本）
3. 创建数据库 `sonic`，字符集选择 `utf8mb4`
4. 设置白名单，允许云服务器内网访问

#### 方案 B：自建 MySQL
在云服务器上使用 Docker 运行 MySQL：
```bash
docker run -d \
  --name mysql \
  -e MYSQL_ROOT_PASSWORD=Sonic!@#123 \
  -p 3306:3306 \
  -v /opt/mysql/data:/var/lib/mysql \
  mysql:8.0
```

### 2. 云服务器配置建议
- **系统**：Ubuntu 20.04/22.04 LTS 或 CentOS 7+
- **CPU**：2 核及以上
- **内存**：4GB 及以上（推荐 8GB）
- **磁盘**：40GB+
- **网络**：开放端口 3000、8761、3306（如自建 MySQL）

**2 核 4G 配置**：可以正常运行所有服务，建议在本地运行 MySQL。

### 3. 配置安全组
在云控制台 - 安全组中添加入站规则：
| 端口范围 | 授权对象 | 描述 |
|---------|---------|------|
| 3000/3000 | 0.0.0.0/0 | Web 应用端口 |
| 8761/8761 | 0.0.0.0/0 | Eureka 注册中心 |
| 3306/3306 | 0.0.0.0/0（仅限自建 MySQL）| MySQL |

**腾讯云安全组路径**：控制台 > 云服务器 > 网络安全 > 安全组

---

## 部署步骤

### 步骤 1：上传部署脚本到云服务器

```bash
# 方式 1：使用 scp 上传
scp deploy-aliyun.sh root@<服务器 IP>:/root/

# 方式 2：使用 Git 克隆
git clone https://github.com/aitoearn/sonic-server.git
cd sonic-server
```

### 步骤 2：执行部署脚本

```bash
# 赋予执行权限
chmod +x deploy-aliyun.sh

# 执行脚本
sudo ./deploy-aliyun.sh
```

脚本会自动：
- 安装 Docker
- 安装 Docker Compose
- 创建部署目录
- 生成配置文件
- 拉取镜像并启动服务

### 步骤 3：配置环境变量

编辑 `/opt/sonic-server/.env` 文件：

```bash
sudo vim /opt/sonic-server/.env
```

**必须修改的配置项：**

```ini
# MySQL 配置
MYSQL_HOST=<云数据库内网地址或 172.17.0.1>
MYSQL_PORT=3306
MYSQL_DATABASE=sonic
MYSQL_USERNAME=root
MYSQL_PASSWORD=<你的数据库密码>

# JWT 密钥（生产环境务必修改）
SECRET_KEY=<生成一个随机字符串>

# 服务器地址
SONIC_SERVER_HOST=0.0.0.0
SONIC_SERVER_PORT=3000
```

### 步骤 4：重启服务

```bash
cd /opt/sonic-server
docker-compose down
docker-compose up -d
```

### 步骤 5：验证部署

```bash
# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 检查服务
curl http://localhost:8761/eureka/apps
```

---

## 访问服务

部署完成后，通过浏览器访问：

- **Web 界面**：`http://<服务器公网 IP>:3000`
- **Eureka 控制台**：`http://<服务器公网 IP>:8761`

默认管理员账号：
- 用户名：`admin`
- 密码：`sonic`

---

## 腾讯云安全组配置

1. 登录 [腾讯云控制台](https://console.cloud.tencent.com/)
2. 进入 **云服务器 > 网络安全 > 安全组**
3. 点击 **添加规则**
4. 添加入站规则：
   - 端口 3000，协议 TCP，源地址 0.0.0.0/0
   - 端口 8761，协议 TCP，源地址 0.0.0.0/0
   - 端口 3306，协议 TCP，源地址 0.0.0.0/0（如本地运行 MySQL）

---

## 常用运维命令

### 查看服务状态
```bash
cd /opt/sonic-server
docker-compose ps
```

### 查看日志
```bash
# 查看所有服务日志
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f sonic-server-controller
```

### 重启服务
```bash
# 重启所有服务
docker-compose restart

# 重启单个服务
docker-compose restart sonic-server-controller
```

### 停止服务
```bash
docker-compose down
```

### 更新版本
```bash
cd /opt/sonic-server
docker-compose pull
docker-compose up -d
```

### 备份数据
```bash
# 备份日志
tar -czf logs-backup-$(date +%Y%m%d).tar.gz /opt/sonic-server/logs/

# 备份文件存储
tar -czf files-backup-$(date +%Y%m%d).tar.gz \
  /opt/sonic-server/keepFiles/ \
  /opt/sonic-server/imageFiles/ \
  /opt/sonic-server/recordFiles/ \
  /opt/sonic-server/packageFiles/
```

---

## 故障排查

### 1. 容器启动失败
```bash
# 查看详细日志
docker-compose logs sonic-server-controller

# 检查配置
docker-compose config
```

### 2. 无法连接数据库
```bash
# 测试数据库连接
docker exec -it sonic-server-controller ping <MYSQL_HOST>

# 检查 MySQL 状态
mysql -h <MYSQL_HOST> -u root -p

# 腾讯云 CDB 需要在控制台设置白名单
```

### 3. 端口被占用
```bash
# 检查端口占用
netstat -tlnp | grep 3000
netstat -tlnp | grep 8761

# 修改端口（编辑 .env 文件后重启）
SONIC_SERVER_PORT=3001
```

### 4. 内存不足
```bash
# 查看内存使用
free -h

# 调整 JVM 参数（可选）
# 编辑 docker-compose.yml，添加 JAVA_OPTS 环境变量
```

---

## 性能优化建议

### 1. JVM 参数调优
在 `docker-compose.yml` 中为各服务添加 JVM 参数：
```yaml
environment:
  - JAVA_OPTS=-Xms256m -Xmx512m
```

### 2. 数据库优化
- 使用云数据库（RDS/CDB）自动优化
- 或调整 MySQL 配置参数

### 3. 日志轮转
创建 `/etc/logrotate.d/sonic-server`：
```
/opt/sonic-server/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
```

---

## 高级部署（可选）

### 使用 HTTPS
1. 申请 SSL 证书（云厂商提供免费证书）
2. 配置 Nginx 反向代理
3. 将 HTTP 重定向到 HTTPS

### 使用负载均衡
适用于多实例部署场景，配置云负载均衡器转发到多个服务器。

### 使用 Kubernetes 服务
- 阿里云 ACK
- 腾讯云 TKE
- 华为云 CCE

---

## 技术支持

- 官方文档：https://sonic-cloud.github.io/
- GitHub: https://github.com/SonicCloudOrg/sonic-server
- 问题反馈：https://github.com/SonicCloudOrg/sonic-server/issues
