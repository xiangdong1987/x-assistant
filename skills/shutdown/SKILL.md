---
name: shutdown
description: 安全关机或重启系统。支持macOS、Linux和Windows系统。
---

# 关机技能

## 功能
安全地关机或重启运行OpenClaw的设备。

## 安全注意事项
⚠️ **重要**：关机前请确保：
1. 保存所有正在进行的工作
2. 确认没有重要的后台进程在运行
3. 了解关机后如何重新启动OpenClaw

## 支持的平台

### macOS
```bash
# 立即关机
sudo shutdown -h now

# 定时关机（10分钟后）
sudo shutdown -h +10

# 重启
sudo shutdown -r now

# 通过AppleScript关机
osascript -e 'tell app "System Events" to shut down'
```

### Linux
```bash
# 立即关机
sudo shutdown now

# 定时关机
sudo shutdown -h +10

# 重启
sudo reboot
```

### Windows
```bash
# 关机
shutdown /s /t 0

# 重启
shutdown /r /t 0

# 定时关机（60秒后）
shutdown /s /t 60
```

## 使用步骤

### 1. 确认系统类型
```bash
uname -a
```

### 2. 检查OpenClaw服务状态
```bash
# 检查OpenClaw网关是否运行
ps aux | grep -i openclaw | grep -v grep
```

### 3. 建议先停止OpenClaw服务
```bash
# 如果OpenClaw网关正在运行
openclaw gateway stop
# 或
pkill -f "openclaw gateway"
```

### 4. 执行关机
根据系统类型选择适当的命令。

## 权限要求
- macOS/Linux：需要sudo权限
- Windows：需要管理员权限

## 恢复OpenClaw服务
关机后重新启动OpenClaw：
```bash
# 启动OpenClaw网关
openclaw gateway start

# 或通过tmux（如果使用tmux会话）
tmux attach -t openclaw
```

## 自动化脚本示例

### macOS关机脚本
```bash
#!/bin/bash
echo "正在停止OpenClaw服务..."
pkill -f "openclaw gateway" || true
sleep 2
echo "正在关机..."
sudo shutdown -h now
```

### 安全关机检查清单
- [ ] 保存所有工作文件
- [ ] 备份重要数据
- [ ] 停止运行中的服务
- [ ] 确认没有未完成的下载/上传
- [ ] 通知其他用户（如有多用户）

## 故障排除

### 如果关机命令被拒绝
1. 检查sudo权限
2. 尝试不使用sudo（某些系统配置允许用户关机）
3. 使用图形界面关机

### 如果OpenClaw无法正常停止
1. 强制停止：`pkill -9 -f "openclaw"`
2. 检查进程：`ps aux | grep openclaw`
3. 手动清理

## 注意事项
1. **数据丢失风险**：强制关机可能导致数据丢失
2. **服务中断**：关机后所有服务将停止
3. **远程访问**：如果远程访问设备，关机后将无法连接
4. **定时任务**：关机可能影响计划的定时任务

## 推荐用法
对于生产环境或重要服务器，建议：
1. 在低流量时段关机
2. 提前通知相关用户
3. 创建系统快照或备份
4. 记录关机原因和时间

## 紧急情况
如果系统无响应，可能需要强制关机：
- macOS：长按电源键
- 大多数电脑：长按电源键5-10秒

**仅在必要时使用强制关机**，这可能导致文件系统损坏。
