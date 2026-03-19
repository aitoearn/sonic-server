-- Sonic Server MySQL 数据库初始化脚本
-- 适用于阿里云 RDS 或自建 MySQL

-- 创建数据库
CREATE DATABASE IF NOT EXISTS sonic
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_unicode_ci;

USE sonic;

-- 如果使用的是 RDS 或已有权限配置，可跳过以下用户创建步骤
-- 创建用户并授权（可选，根据实际需求修改）
-- CREATE USER IF NOT EXISTS 'sonic'@'%' IDENTIFIED BY 'Sonic!@#123';
-- GRANT ALL PRIVILEGES ON sonic.* TO 'sonic'@'%';
-- FLUSH PRIVILEGES;

-- 表结构将由应用自动创建（Spring Data JPA）
-- 如需手动导入，可在应用启动后查看应用生成的 DDL

-- 注意事项：
-- 1. 确保 MySQL 版本 >= 5.7
-- 2. 确保字符集为 utf8mb4
-- 3. 确保数据库用户有创建表的权限
-- 4. 如使用阿里云 RDS，建议在 RDS 控制台设置白名单
