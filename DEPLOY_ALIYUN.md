# Sonic Server 阿里云部署指南

本文档介绍如何将 Sonic Server 部署到阿里云 ECS 服务器。

## 前置准备

### 1. 阿里云资源准备

#### 方案 A：使用阿里云 RDS（推荐）
1. 登录阿里云控制台
2. 创建 RDS MySQL 实例（建议 5.7+ 版本）
3. 创建数据库 `sonic`，字符集选择 `utf8mb4`
4. 设置白名单，允许 ECS 内网访问

#### 方案 B：自建 MySQL
在 ECS 上使用 Docker 运行 MySQL：
```bash
docker run -d \
  --name mysql \
  -e MYSQL_ROOT_PASSWORD=Sonic!@#123 \
  -p 3306:3306 \
  -v /opt/mysql/data:/var/lib/mysql \
  mysql:8.0
```

### 2. ECS 配置建议
- **系统**：Ubuntu 20.04/22.04 LTS 或 CentOS 7+
- **CPU**：2 核及以上
- **内存**：4GB 及以上（推荐 8GB）
- **磁盘**：40GB+
- **网络**：开放端口 3000、8761、3306（如自建 MySQL）

### 3. 配置安全组
在阿里云控制台 - 安全组中添加入站规则：
| 端口范围 | 授权对象 | 描述 |
|---------|---------|------|
| 3000/3000 | 0.0.0.0/0 | Web 应用端口 |
| 8761/8761 | 0.0.0.0/0 | Eureka 注册中心 |
| 3306/3306 | 0.0.0.0/0（仅限自建 MySQL）| MySQL |

---

## 部署步骤

### 步骤 1：上传部署脚本到 ECS

```bash
# 方式 1：使用 scp 上传
scp deploy-aliyun.sh root@<ECS_IP>:/root/

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

### 步骤 3：配置环境变量

编辑 `/opt/sonic-server/.env` 文件：

```bash
sudo vim /opt/sonic-server/.env
```

**必须修改的配置项：**

```ini
# MySQL 配置
MYSQL_HOST=<RDS 内网地址或 ECS 内网 IP>
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

- **Web 界面**：`http://<ECS 公网 IP>:3000`
- **Eureka 控制台**：`http://<ECS 公网 IP>:8761`

默认管理员账号：
- 用户名：`admin`
- 密码：`sonic`

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
  - JAVA_OPTS=-Xms512m -Xmx1024m
```

### 2. MySQL 优化
- 使用阿里云 RDS（自动优化）
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
1. 申请 SSL 证书（阿里云免费证书）
2. 配置 Nginx 反向代理
3. 将 HTTP 重定向到 HTTPS

### 使用 SLB 负载均衡
适用于多实例部署场景，配置 SLB 转发到多个 ECS。

### 使用 ACK 容器服务
参考官方文档使用阿里云 Kubernetes 服务部署。

---

## 技术支持

- 官方文档：https://sonic-cloud.github.io/
- GitHub: https://github.com/SonicCloudOrg/sonic-server
- 问题反馈：https://github.com/SonicCloudOrg/sonic-server/issues
