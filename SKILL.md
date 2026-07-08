# cc-planet — 飞行动画通知

在屏幕上显示一架拖曳横幅飞过的飞机，用于 CI/CD 构建状态通知或日常消息提醒。

## 安装

### 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/gezihua123/cc-planet/main/install_pkg.sh | bash
```

安装到 `~/bin/cc-plane/`，自动加入 PATH。

### 手动安装

```bash
# 下载并解压最新版
curl -fsSL https://api.github.com/repos/gezihua123/cc-planet/releases/latest \
  | grep "tarball_url" \
  | cut -d '"' -f 4 \
  | xargs curl -fsSL \
  | tar -xz --strip-components=1

# 或指定版本
curl -fsSL https://github.com/gezihua123/cc-planet/releases/download/v0.0.3/cc-planet-v0.0.3.tar.gz | tar -xz
```

### 从源码编译

```bash
git clone git@github.com:gezihua123/cc-planet.git
cd cc-planet
./build.sh
```

## 用法

```bash
cc-planet [--success | --failure | --blocked] [<消息文本>]
```

### 示例

```bash
# 简单的通知
cc-planet "Hello World"

# 成功状态
cc-planet --success "Deploy complete"

# 失败状态
cc-planet --failure "Test failed"

# 阻塞状态
cc-planet --blocked "Waiting review"
```

### 状态说明

| 参数 | 颜色 | 默认消息 |
|------|------|---------|
| `--success` | ✅ 绿色 | "Build passed" |
| `--failure` | ❌ 红色 | "Test failed" |
| `--blocked` | ⏳ 黄色 | "Waiting review" |
| _(无)_ | ✈️ 默认 | 自定义文本 |

## 配置

通过 `~/bin/cc-plane/env.json` 自定义图片、emoji 和默认文案。

```json
{
    "success": {
        "image": "/path/to/success-plane.png",
        "emoji": "✅",
        "prompt": "All good!"
    }
}
```

## CI/CD 集成

### GitHub Actions

```yaml
- name: Notify
  run: |
    cc-planet --success "Build #${{ github.run_number }} passed"
```

### Claude Code 集成

```bash
echo '{"stop_reason":"end_turn"}' | ~/bin/cc-plane/cc-notify.py
```

## 发布

```bash
# patch 版本递增（默认）
./release.sh

# minor 版本递增
./release.sh minor

# major 版本递增
./release.sh major
```

发布流程：编译 → 打包资源 → 打 tag → 推 GitHub Release → 更新 install_pkg.sh 版本号 → 提交推送

## 项目结构

```
├── main.swift       # 主程序
├── build.sh         # 编译脚本
├── release.sh       # 发布脚本
├── install_pkg.sh   # 安装脚本
├── cc-notify.py     # CI/CD 通知辅助
├── env.json         # 运行时配置模板
└── plane.png        # 飞机图片源文件
```

## 链接

- GitHub: https://github.com/gezihua123/cc-planet
- Releases: https://github.com/gezihua123/cc-planet/releases
