# Proxy 编译与测试

改完 proxy（Go 代码）后的编译和重新测试方式。

---

## 一、编译 Proxy

### 1. 仅编译二进制（推荐日常开发）

在**项目根目录**执行：

```bash
./macos/scripts/build_proxy.sh
```

- 输出：`proxy/xassistant-proxy`（未签名，适合终端直接跑）
- 若脚本无执行权限：`chmod +x macos/scripts/build_proxy.sh` 后再执行

或进入 proxy 目录用 go 直接编译：

```bash
cd proxy
go build -o xassistant-proxy .
```

### 2. 编译并打进 Flutter macOS 应用

- 用 **Xcode** 或 **Flutter** 构建 macOS 时，会先跑 `macos/scripts/build_proxy.sh`（带 `BUILD_FOR_APP=1`），产物在 `macos/Runner/Resources/xassistant-proxy`，并随应用打包进 `.app`。
- 命令行完整构建示例：

```bash
flutter build macos
# 或
cd macos && xcodebuild -scheme Runner -configuration Debug
```

Debug 构建下 proxy 不签名；Release 构建会尝试用 `Proxy.entitlements` 签名。

---

## 二、本地测试 Proxy（不通过 App）

### 1. 直接运行

```bash
./proxy/xassistant-proxy -h
./proxy/xassistant-proxy -port 8443 -host 0.0.0.0
```

按需加参数，例如：

```bash
./proxy/xassistant-proxy -port 8443 -host 0.0.0.0 \
  -openclaw -openclaw-token YOUR_TOKEN \
  -allow-local-no-auth \
  -skills-path "$(pwd)/skills" \
  -workdir "$(pwd)/proxy" \
  -log ~/Library/Logs/xassistant-proxy/proxy.log
```

### 2. 健康检查

代理起来后：

```bash
curl -s http://127.0.0.1:8443/api/health
```

返回 JSON 即表示正常。

### 3. 阶段轮询间隔（调试用）

可缩短 phase 轮询间隔方便看流转：

```bash
./proxy/xassistant-proxy -port 8443 -phase-watcher-interval 10 ...
```

---

## 三、在 App 内重新测试（用新 Proxy）

### 1. Debug 运行 + 项目内二进制

- 先按「一、1」编译出 `proxy/xassistant-proxy`。
- 用 **Debug** 跑 Flutter（`flutter run -d macos` 或 Xcode Run）。
- App 内「代理配置」不填路径或留空时，会优先用项目里的 `proxy/xassistant-proxy`，改完 proxy 只需重新执行 `./macos/scripts/build_proxy.sh`，再在 App 里重启代理即可，无需重编 App。

### 2. 使用 .app 内打包的 Proxy

- 先执行一次 **Flutter macOS 构建**（或 Xcode 构建），让脚本把 proxy 编译到 `Runner/Resources` 并打进 `.app`。
- 运行该构建出的 App，在代理配置页不填路径，即会用 `.app` 内的 proxy。
- 每次改完 proxy 后需**重新构建 macOS 应用**，再运行新 App 才能用到新二进制。

---

## 四、快速自检清单

| 步骤 | 命令/操作 |
|------|-----------|
| 1. 编译 proxy | `./macos/scripts/build_proxy.sh` |
| 2. 终端试跑 | `./proxy/xassistant-proxy -port 8443` |
| 3. 健康检查 | `curl http://127.0.0.1:8443/api/health` |
| 4. App 内测试（Debug） | 保持 `proxy/xassistant-proxy` 存在，Flutter Run 后在 App 里启动/重启代理 |
| 5. 看日志 | 启动时加 `-log /path/to/proxy.log`，或 App 配置页设置日志路径后「查看日志」 |
