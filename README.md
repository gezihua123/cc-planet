# cc-planet — 飞行动画通知工具

在屏幕上显示一架拖曳横幅飞过的飞机，用于 CI/CD 构建状态通知或日常消息提醒。

## 安装

### 方式一：安装脚本（推荐）

一行命令即可完成安装，自动安装到 `/usr/local/bin/`。

```bash
curl -fsSL https://raw.githubusercontent.com/gezihua123/cc-planet/main/install_pkg.sh | bash
```

脚本会自动：
1. 检测系统架构（arm64 / x86_64）
2. 从 GitHub Releases 下载最新版二进制
3. 安装到 `/usr/local/bin/`
4. 创建 `cc-notify` → `cc-planet` 符号链接（兼容旧 hook）
5. 验证安装是否成功

> 安装使用 `sudo` 写入 `/usr/local/bin/`，如遇权限提示请输入密码。

### 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/gezihua123/cc-planet/main/install_pkg.sh | bash -s -- --uninstall
```

卸载脚本会自动删除 `cc-planet` 二进制及 `cc-notify` 符号链接。

### 方式二：手动下载

直接访问 [Releases 页面](https://github.com/gezihua123/cc-planet/releases) 下载 `cc-planet-*.tar.gz`，解压后即可使用。

### 方式三：从源码编译

```bash
git clone git@github.com:gezihua123/cc-planet.git
cd cc-planet
./build.sh
```

产物：`cc-planet`（通用二进制，支持 arm64 + x86_64，最低 macOS 11）

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
./cc-planet --notify <消息>
echo '<json>' | ./cc-planet --json
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `--success` | 成功状态（✅ 绿色主题图片） |
| `--failure` | 失败状态（❌ 红色主题图片） |
| `--blocked` | 阻塞状态（⏳ 黄色主题图片） |
| `--notify <消息>` | 通知模式，显示纯文本横幅（防并发） |
| `--json` | 从 stdin 读取 JSON 事件并解析通知 |
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

# 通知模式（防并发，适合 CI/CD 钩子）
./cc-planet --notify "Something happened"

# 从 JSON 事件解析通知（取代旧版 cc-notify）
echo '{"last_assistant_message":"完成","stop_reason":"stop"}' | ./cc-planet --json

# 处理 AskUserQuestion 事件
./cc-planet --json < events.json
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

### Claude Code 集成

当 Claude Code 会话结束时收到通知：

```bash
echo '{"last_assistant_message":"任务完成","stop_reason":"stop"}' | ./cc-planet --json
```

---

## cc-notify 符号链接

`cc-notify` 是 `cc-planet` 的符号链接（安装时自动创建），用于兼容旧版 hook 调用。

```bash
cc-notify "Deploying to production"
cc-notify --success "Build passed"
echo '{"last_assistant_message":"Hello"}' | cc-notify --json
```

> **完全等价于** `cc-planet --notify "..."` / `cc-planet --json`

### 环境变量

| 变量 | 说明 |
|------|------|
| `CC_PLANET_BIN` | cc-planet 二进制路径 |

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

## 发布

```bash
# patch 版本递增（默认）
./release.sh

# minor 版本递增
./release.sh minor

# major 版本递增
./release.sh major
```

发布流程：编译 → 打包资源 → 打 tag → 推 GitHub Release → 更新 install_pkg.sh

---

## 开发

### 项目结构

```
├── main.swift       # 主程序（含内置图片 + 通知事件处理）
├── build.sh         # 编译脚本
├── release.sh       # 发布脚本（编译 → 打包 → 推 GitHub Release）
├── install_pkg.sh   # 安装/卸载脚本（从 GitHub Release 下载安装）
├── env.json         # 运行时配置模板
├── plane.png        # 原始图片源文件
├── version.properties # 版本号配置
├── README.md        # 中文文档
├── README.en.md     # 英文文档
└── SKILL.md         # Claude Code 技能描述
```

### 添加新状态

1. 在 `EnvConfig` 中添加新字段（如 `pending`）
2. 在 `subscript(status:)` 中添加 case
3. 在命令行解析的 `statusFlags` 集合中添加对应 flag
4. `env.json` 中添加对应的配置组

---

## License

MIT
