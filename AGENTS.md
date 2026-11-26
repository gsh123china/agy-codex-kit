# AGENTS.md（仅限 agy-codex-kit 仓库自举维护）

> **作用域声明**：本文件仅在维护与升级 `agy-codex-kit` 仓库自身时生效（多工作区并存时切勿套用至其他业务仓库）。**严禁将本文件纳入 `install.sh` 软链部署目标**（新建业务仓库请使用 `templates/AGENTS.md.template`）。

## 1. 模块边界与自举分工
- **规则、提示词、模板与文档（Antigravity 主笔）**：`antigravity/GEMINI.md`、`antigravity/skills/codex-executor/SKILL.md`、`templates/*`、`docs/*`、`README.md`。守住意图边界、克制裁剪与自然中文表达，严防规则膨胀与过度防御八股化。
- **工程脚本与交叉审查（Codex 强项介入）**：`antigravity/skills/codex-executor/scripts/run-codex.sh`、`antigravity/statusline.sh`、`install.sh` 的实现、重构与边界测试，以及升级前 `--review` 与落地后 `--code-review` 的跨文件一致性挑刺。
- **契约联动地图**：凡修改核心协作协议、命令行参数或输出信号（如 `[BLOCKED]`、`CODEX_STATUS`、`--code-review`），必须同步核查 `GEMINI.md`、`SKILL.md`、`run-codex.sh`、`templates/*`、`README.md` 与 `docs/Antigravity+Codex协作配置备忘.md`。

## 2. 自举专属安全规程（Stage 1 → Stage 2）
- **禁止运行中覆写宿主脚本**：`~/.gemini/` 直接软链至本仓库。若需通过 Codex 修改 `run-codex.sh` 自身，必须先复制稳定副本（如 `cp antigravity/skills/codex-executor/scripts/run-codex.sh /tmp/run-codex-host.sh`）作为宿主驱动，严禁让运行中的 `run-codex.sh` 直接覆写自身；改完后再用仓库新版跑自检。
- **微缩靶场验收**：涉及协作流程、提示词或脚本行为变更时，须在 `/tmp/` 建立临时沙箱仓库实测跑通闭环，并在验收后清理临时目录与测试报告。
- **生效边界**：已有脚本与 `SKILL.md` 修改经软链即时生效；新增脚本或 Skill 目录需补跑 `./install.sh`；修改 `antigravity/GEMINI.md` 后需新开 `agy` 会话加载最新全局系统提示词。

## 3. 核心不变量与工程红线
- **行预算铁律**：`antigravity/GEMINI.md` 严格控制在 **≤ 60 行**（增新必审旧，实现细节下沉至 `SKILL.md` 或 `run-codex.sh`）。
- **脱敏与可移植性**：严禁在仓库任意文件硬编码宿主机用户路径（如 `/home/<user>`），严禁提交真实凭证或宿主机私密配置（`auth.json`、`config.toml`、`settings.json`）。
- **测试与 Git 红线**：严禁为通过验收而放宽测试标准；除非用户明确指令，禁止自动执行 `git add` / `git commit`；**永远禁止**执行 `git push`。

## 4. 标准无头验收命令
```bash
# 1) 脚本语法、JSON 格式、GEMINI.md 行预算与宿主机路径脱敏检查
bash -n install.sh antigravity/statusline.sh antigravity/skills/codex-executor/scripts/run-codex.sh && \
jq empty examples/antigravity.settings.json.example && \
test "$(wc -l < antigravity/GEMINI.md)" -le 60 && \
! grep -rnE '/(home|Users)/[A-Za-z0-9._-]+' . --exclude-dir=.git

# 2) 隔离环境安装幂等性及“不部署根目录 AGENTS.md”红线校验
TMP_G="$(mktemp -d)" && GEMINI_HOME="$TMP_G" ./install.sh >/dev/null && \
GEMINI_HOME="$TMP_G" ./install.sh >/dev/null && \
test ! -e "$TMP_G/AGENTS.md" && rm -rf "$TMP_G"
```

## 5. 关键决策溯源
- **根目录 `AGENTS.md` 不纳入 `install.sh`**：仅在工作目录切入 `agy-codex-kit` 时激活自举规则；否决将其软链至 `~/.gemini/` 或 `~/.codex/`（会污染所有外部业务仓库上下文）。
- **`GEMINI.md` 死守 60 行上限且由 Antigravity 主笔**：防止多轮自举堆叠防御条款稀释模型注意力；否决由 Codex 直接改写全局规则正文。
