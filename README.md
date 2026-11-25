# agy-codex-kit

**Antigravity（统筹 / 架构师）+ OpenAI Codex CLI（严谨审查 / 细节落地）** 的个人全局协作配置仓库。

采用 **“本仓库作为单一真相源 + `install.sh` 软链接部署”** 的 dotfiles 模式：日常优化规则、Skill 或脚本时，改动直接落在本仓库并由 Git 记录完整演进履历；换机器时克隆后执行一条命令即可复用。

---

## 目录结构

```text
agy-codex-kit/
├── README.md                                   # 使用与部署说明
├── .gitignore                                  # 禁止提交密钥、本地备份与宿主机私密配置
├── install.sh                                  # 幂等软链部署脚本（自动备份旧文件，支持 --uninstall）
├── antigravity/                                # 自动软链到 ~/.gemini/
│   ├── GEMINI.md                               # -> ~/.gemini/GEMINI.md（全局角色分工与架构权衡原则）
│   └── skills/
│       └── codex-executor/                     # -> ~/.gemini/config/skills/codex-executor
│           ├── SKILL.md                        # 设计审查 / 任务派发 / 验收闭环 SOP
│           └── scripts/
│               └── run-codex.sh                # 封装 codex exec（--review / --resume / --effort / --safe）
├── templates/                                  # 新代码仓库初始化模板（按需拷贝）
│   ├── AGENTS.md.template                      # Antigravity 与 Codex 共同读取的仓库契约
│   ├── design-doc.md.template                  # 给 --review 只读审查用的设计方案模板
│   └── task-spec.md.template                   # 含 Non-Goals 与验收命令的原子任务单模板
├── examples/                                   # 脱敏配置参考（绝不自动覆盖宿主机）
│   ├── codex.config.toml.example               # ~/.codex/config.toml 参考
│   └── antigravity.settings.json.example       # ~/.gemini/antigravity-cli/settings.json 参考
└── docs/
    └── Antigravity+Codex协作配置备忘.md         # 完整架构、权限策略与排坑记录
```

---

## 新机器快速部署

### 1. 安装前置 CLI
* 已安装 Antigravity CLI（`agy`）
* 安装并登录 OpenAI Codex CLI：
  ```bash
  npm install -g @openai/codex
  codex login
  ```

### 2. 克隆仓库并建立软链接
```bash
git clone <your-github-repo-url> ~/agy-codex-kit
cd ~/agy-codex-kit
./install.sh
```
> 若 `~/.gemini/` 下已有同名真实文件或目录，`install.sh` 会自动备份至 `~/.gemini/backups/agy-codex-kit-<timestamp>/`（避开 `skills/` 扫描目录，防止重复加载）。

### 3. 按机器安全等级配置权限
* **隔离虚拟机 / 无人值守长任务**：在 `agy` 内执行 `/config` 切换为 `Turbo`，或用 `agy --dangerously-skip-permissions` 启动；
* **主力机 / 敏感环境**：保持 `Default` 或 `Auto` 沙箱，在 `/permissions` 中放行 `command(codex exec)`，派单时传 `--safe`。

重启一次 `agy` 会话即可生效。

---

## 日常使用与演进同步

### 推理强度分级约定（显式指定 `--effort`，不假设本地默认）
* 常规实现、常规升级、常规设计 Review：`--effort xhigh`
* 复杂架构 Review、高风险改造、疑难 Bug：`--effort max`

### 常用派单命令
```bash
# 1. 设计方案只读 Review（不改代码，输出分级风险与复杂度代价）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --review --effort xhigh docs/design/feature.md .

# 2. 派发原子任务单落地实现
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --effort xhigh docs/tasks/T01.md .

# 3. 验收未通过时续接上次 session 定向返工
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --resume <session-id> --effort xhigh docs/tasks/T01-rework.md .
```

### 多机同步与留档
* 修改规则、Skill 或脚本后，直接在本仓库执行 `git diff` → `git commit` → `git push`；
* 其他机器只需 `git pull`（若新增了新的 Skill 目录，补跑一次 `./install.sh`）。

### 安全卸载
```bash
./install.sh --uninstall
```
仅移除指向本仓库的软链接，不触碰其他文件。

---

## 安全提醒

**绝不向本仓库提交以下内容**：
* `~/.codex/auth.json`、`~/.codex/config.toml`（可能含 API Key、私有代理或中转配置）
* `~/.gemini/antigravity-cli/settings.json`（不同机器权限预设不同）

更多架构背景与避坑记录见 [docs/Antigravity+Codex协作配置备忘.md](docs/Antigravity+Codex协作配置备忘.md)。
