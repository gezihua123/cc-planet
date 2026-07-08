# cc-planet — 飞行动画通知工具

在屏幕上显示一架拖曳横幅飞过的飞机，用于 CI/CD 构建状态通知或日常消息提醒。

## 安装

### 方式一：安装脚本（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/gezihua123/cc-planet/main/install_pkg.sh | bash
```

脚本会自动下载最新 Release 并安装到 `~/bin/cc-plane/`，无需 sudo。

### 方式二：手动下载

```bash
# 下载最新版 tarball
curl -fsSL https://api.github.com/repos/gezihua123/cc-planet/releases/latest \
  | grep tarball_url \
  | cut -d '"' -f 4 \
  | wget -O - -qi - \
  | tar -xz
```

或直接访问 [Releases 页面](https://github.com/gezihua123/cc-planet/releases) 下载 `cc-planet-*.tar.gz`。

### 方式三：从源码编译

```bash
./build.sh
```

## 快速开始

```bash
# 编译
./build.sh

# 运行
./cc-planet "Hello World"
./cc-planet --success "Build passed"
```

---

## 命令行用法

```
./cc-planet [--success | --failure | --blocked] [<消息文本>]
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `--success` | 成功状态（✅ 绿色/成功主题图片） |
| `--failure` | 失败状态（❌ 红色/失败主题图片） |
| `--blocked` | 阻塞状态（⏳ 黄色/等待主题图片） |
| `<消息文本>` | 可选。显示在飞机横幅上的文字（限 22 字） |

### 示例

```bash
# 无状态，自定义消息
./cc-planet "Deploying to production"

# 带状态 + 默认消息
./cc-planet --success
# → 横幅: "✅ Build passed"

./cc-planet --failure
# → 横幅: "❌ Test failed"

./cc-planet --blocked
# → 横幅: "⏳ Waiting review"

# 带状态 + 自定义消息
./cc-planet --success "v2.3 deployed"
# → 横幅: "✅ v2.3 deployed"
```

---

## `env.json` 配置

通过 `env.json` 自定义每个状态的图片、emoji 和默认文案。程序启动时依次从**当前目录**和**二进制所在目录**查找 `env.json`。

### 字段说明

每个状态可以配置三项：

| 字段 | 类型 | 说明 |
|------|------|------|
| `image` | string (路径) | 飞机图片 PNG 路径，绝对路径或相对路径 |
| `emoji` | string | 消息横幅前缀 emoji，例如 `"✅"` |
| `prompt` | string | 该状态的默认消息文本 |

### 示例配置

```json
{
    "default": {
        "image": "/path/to/default-plane.png",
        "emoji": "✈️",
        "prompt": "Hello"
    },
    "success": {
        "image": "/path/to/success-plane.png",
        "emoji": "✅",
        "prompt": "Build passed"
    },
    "failure": {
        "image": "/path/to/failure-plane.png",
        "emoji": "❌",
        "prompt": "Test failed"
    },
    "blocked": {
        "image": "/path/to/blocked-plane.png",
        "emoji": "⏳",
        "prompt": "Waiting review"
    }
}
```

### 消息组装规则

```
最终横幅 = [状态 emoji] + [自定义消息 | 状态默认 prompt]
```

- 指定 `--success` + 自定义消息 → `"✅ Deployed to prod"`
- 指定 `--success` + 无自定义消息 → `"✅ Build passed"`（使用 `prompt`）
- 无 emoji 配置 → 横幅不显示 emoji

### 兼容旧格式

`env.json` 兼容旧版纯字符串写法，以下格式仍然支持：

```json
{
    "success": "/path/to/success-plane.png",
    "failure": "/path/to/failure-plane.png"
}
```

### 图片加载优先级

```
指定状态的 image → default 的 image → 顶层 image（旧版）→ 编译时嵌入的内置图片
```

### 搜索路径

`env.json` 搜索顺序（先找到的生效）：

1. 进程当前工作目录（`FileManager.currentDirectoryPath`）
2. 可执行文件所在目录（`argv[0]` 的父目录）

---

## CI/CD 集成

### GitHub Actions

```yaml
- name: Build & Notify
  run: |
    ./cc-planet --success "Build #${GITHUB_RUN_NUMBER} passed"
```

### 自定义构建脚本

```bash
#!/bin/bash
if ./build.sh; then
    ./cc-planet --success "Build OK"
else
    ./cc-planet --failure "Build failed"
fi
```

---

## 编译说明

```bash
./build.sh
```

产物：`cc-planet`（通用二进制，支持 arm64 + x86_64，最低 macOS 11）

### 依赖

- macOS 11+
- Swift（编译时需要，运行时不需要）

---

## 开发

### 项目结构

```
├── main.swift       # 主程序（含内置图片 base64）
├── build.sh         # 编译脚本
├── release.sh       # 发布脚本（编译 → 打包 → 推 GitHub Release）
├── install_pkg.sh   # 安装脚本（从 GitHub Release 下载安装）
├── cc-notify.py     # CI/CD 通知辅助脚本
├── env.json         # 运行时配置（可选）
└── plane.png        # 原始图片源文件
```

### 添加新状态

1. 在 `EnvConfig` 中添加新字段（如 `pending`）
2. 在 `subscript(status:)` 中添加 case
3. 在命令行解析的 `statusFlags` 集合中添加对应 flag
4. `env.json` 中添加对应的配置组

---

## License

MIT
