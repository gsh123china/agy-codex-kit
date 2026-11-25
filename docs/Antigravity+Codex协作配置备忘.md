# Antigravity + Codex 协作配置备忘（方案 A · 全局版）

> **核心理念**：代码可以重写，会话可以重开，真正昂贵且稀缺的是**定义系统真相（意图、边界、行为评估、决策溯源）与人的真实理解**。之所以协作，是因为 Codex Token 成本低、仓库分析幻觉少、工程推理严谨，但缺乏“艺术细胞”（UI/UX 审美差、行文晦涩、易过度防御）。因此由 **Antigravity 担任统筹架构师（对齐意图、筛除 Gap、权衡裁剪、审美创意、表达润色、最终验收）**，由 **Codex 担任严谨审查与落地工程师（仓库事实核查、独立代码复审、原子实现、行为测试、修 Bug）**，面向可随时回退的虚拟机开发环境与无人值守长任务。

---

## 一、协作架构与双层判断闭环

```mermaid
flowchart LR
    U["用户（意图与拍板）"] -->|"1. 需求与红线"| A["Antigravity（统筹/架构师）"]
    A -->|"2. 问清关键模糊点（消第一层 Gap）"| D["短设计稿 docs/design/*.md"]
    D -->|"3. --review 只读核查"| CR["Codex（仓库事实审查）"]
    CR -->|"4. 分级风险 + 复杂度代价"| W["Antigravity 架构权衡"]
    W -->|"5. 骨架先行 + Non-Goals + 拆原子单"| T["任务单 docs/tasks/*.md"]
    T -->|"6. run-codex.sh 独立会话落地"| C["Codex（执行工程师）"]
    C -->|"7. 实现 + 主动交代自行假设"| R["/tmp/codex-reports/*.md"]
    R --> A2["Antigravity 终验（可选 --code-review）"]
    A2 -->|"8. 筛第二层 Gap + 审 diff + 跑评估"| V{"通过？（最多2次 --resume）"}
    V -->|"第 1~2 次小偏差：定向返工"| T
    V -->|"超 2 次不过：回退 + 总结教训重开新会话"| T
    V -->|"通过：原地沉淀溯源 + 精炼汇报"| U
```

### 1. 工程判断的五条核心纪律（汲取自《从写代码到做判断》）

| 纪律 | 解决的痛点 | 在本协作体系中的落地机制 |
| :--- | :--- | :--- |
| **双层 Gap 穿透**（Spec / Defaults / Gap） | Agent 私自替人做决定，会话一关只剩代码知道“是什么”却不知“为什么” | **对上**：Antigravity 用“三条门槛”区分 Defaults（直接定）与 Gap（先问用户）；**对下**：`run-codex.sh` 强制要求 Codex 在报告中单列**未明说但自行做出的假设（Unstated Decisions）**，终验时逐条过筛 |
| **三条门槛筛重留轻** | 什么都记会淹没在噪音里，什么都不记系统会失忆 | 仅当决定满足任一条时才升格为必审 Gap / 必记溯源：① **回退代价高或危险**（钱、数据完整性、删除、安全、对外契约）；② **内行外人看莫名其妙**（魔法数字、反直觉限制）；③ **跨模块边界与数据归属** |
| **骨架先行 + 快慢层分级** | 模块切太碎导致接缝爆炸；底层小改动引发全局故障 | 按“独立变化的决策 + **数据归属**”划边界，多模块先派**最简端到端骨架单（Walking Skeleton）**；区分**快层**（UI/文案）与**慢层**（核心模型、公共契约、换底层库、**删旧功能**），慢层必做前置 `--review` |
| **写审分离 + 硬核行为评估** | 写代码的会话顺着原思路自我宽容；绿灯伪测试骗人 | 严禁 Codex 为过测删改/放宽既有测试标准；测试优先测**外部可观测行为**而非绑死私有实现；慢层改动支持 `--code-review` 开启干净只读会话独立挑错 |
| **两次不过止损重开 + 知识搬出会话** | 同一会话反复纠偏残留错误思路，越改越乱；`/compact` 压缩丢失约束 | `--resume` 连续返工**最多 2 次**，仍不过立即仅撤销本任务改动（勿伤用户原有未提交修改）并带教训开全新会话；收尾时将关键决定与**被否决方案及理由**以 3~5 行原地更新至 `AGENTS.md` 或设计稿 |

### 2. 设计 Review 与“严谨性 vs 可维护性”权衡机制

| Review 意见分级 | 判定标准 | Antigravity 的处理动作 |
| :--- | :--- | :--- |
| **必改项（Adopt）** | 与现有代码库不符的事实偏差、跨边界/数据归属冲突、主路径缺陷、安全或数据一致性风险 | 直接采纳并修订设计方案 |
| **审慎权衡项（Trade-off）** | 极端临界条件、防御式冗余兜底 | 权衡**触发概率与后果** vs **可理解性/可维护性代价**；性价比低时改用清晰的接口契约/前置假设约束 |
| **明确驳回项（Reject）** | 得不偿失的过度防御逻辑或顺手扩范围建议 | 明确不采纳，写入实现任务单 **Non-Goals**，并将重要否决理由原地留痕至设计稿 |

### 3. 规则与配置隔离机制

| 文件 / 目录 | 读取方 | 定位与职责 |
| :--- | :--- | :--- |
| `~/.gemini/GEMINI.md` | **仅 Antigravity** | 全局统筹准则（严格控制在 60 行内）：意图边界、消除 Gap、快慢层权衡、强制终验与 Git 限制 |
| `~/.gemini/config/skills/codex-executor/` | **仅 Antigravity** | 派单标准 SOP 与封装脚本（不放 `~/.agents/skills/`，避免 Codex 误读） |
| `<repo>/AGENTS.md` | **Antigravity + Codex 共读** | 单仓库持久真相：模块边界与数据归属、构建与行为评估命令、核心不变量与关键决策溯源 |
| `<repo>/.codex/config.toml` 或 `~/.codex/config.toml` | **仅 Codex** | Codex 默认模型、推理强度、MCP 工具等配置 |

### 4. 委派边界（扬长避短）
* **优先派给 Codex**：仓库事实审查、落地后独立代码复审、核心业务逻辑实现、较大重构、多文件修改、行为测试编写、复杂 Bug 定位与修复。
* **由 Antigravity 直接处理、不要交给 Codex**：
  1. **UI/UX 与创意审美类**：界面设计、视觉排版、CSS/样式美学、交互动效、视频生成与动画编排、图表/架构图美化等（混合型前端任务仅将纯逻辑/接口/测试拆给 Codex，UI 表现层由 Antigravity 把控）；
  2. **文档、文章与交互文案类**：写文档、讲义、文章、调研报告、分析问答与用户交互文案；
  3. **小改动与显式指定**：用户明确要求 Antigravity 直接改代码，或 15 行以内的极小改动（一句话说清的小事直接做，不套重流程）。
* **表达润色与防认知债**：禁止原样生搬 Codex 晦涩生硬的原始报告；面向用户的计划与汇报坚持“简短好读、读完能拍板”，聚焦行为承诺、关键取舍/否决理由与筛出的待拍板项。

---

## 二、已落盘的全局文件清单

1. **全局角色规则**：[`~/.gemini/GEMINI.md`](../antigravity/GEMINI.md)
2. **全局派单 Skill**：[`~/.gemini/config/skills/codex-executor/SKILL.md`](../antigravity/skills/codex-executor/SKILL.md)
3. **全局执行脚本**：[`~/.gemini/config/skills/codex-executor/scripts/run-codex.sh`](../antigravity/skills/codex-executor/scripts/run-codex.sh)
   * 自动补全 `mise` / `~/.local/bin` / `~/.bun/bin` 到 `PATH`；
   * 支持四种模式：编码前 `--review`（只读设计审查）、默认 `exec`（原子任务实现）、`--resume`（最多 2 次定向返工）、编码后 `--code-review`（干净会话只读代码复审，写审分离）；
   * 强制要求实现/返工汇报单列 `Unstated Decisions`（自行假设），并明令禁止篡改既有测试标准或自动提交 Git；
   * 自动将报告写入 `/tmp/codex-reports/[review-|code-review-|resume-]<task>-<timestamp>.md`。
4. **自定义底部状态栏**：[`~/.gemini/antigravity-cli/statusline.sh`](../antigravity/statusline.sh)

---

## 三、权限与沙箱配置

### 为什么默认沙箱下无法调用 Codex？
开启 Antigravity 终端沙箱时，存在三重拦截：
1. 宿主机通过 `mise` 管理的 Node 路径（如 `~/.local/share/mise/installs/node/22/bin`）未挂载进沙箱；
2. Codex 凭证与配置目录 `~/.codex` 对沙箱不可见；
3. 沙箱默认断外网，Codex 无法连接 OpenAI API。

### 1. Antigravity 侧（虚拟机最大权限配置）
* **方式 A（持久化，推荐）**：在 Antigravity CLI 中输入 `/config` 或 `/permissions`，将权限预设切换为 **`Turbo`**。
* **方式 B（按会话生效）**：启动 CLI 时携带参数 `agy --dangerously-skip-permissions`。
* **备选（非 VM / 敏感环境）**：保持 `Default` 或 `Auto` 预设，在 `/permissions` 中仅放行 `command(codex exec)`，派单时启用 `--safe`。

### 2. Codex 侧
* **默认（VM 无人值守模式）**：`run-codex.sh` 在 `exec`/`resume` 下附加 `--dangerously-bypass-approvals-and-sandbox`；`--review` 与 `--code-review` 始终强制 `--sandbox read-only`。
* **敏感仓库收紧权限**：加上 `--safe`，自动切换为 `--sandbox workspace-write`。

---

## 四、日常使用速查

### 1. 派单脚本用法
```bash
# 1) 编码前：设计方案只读 Review（常规用 xhigh；复杂架构/慢层改造传 max）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --review --effort xhigh <design-doc> [workdir]

# 2) 编码中：派发原子任务单落地实现（一单只做一件事）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --effort xhigh <task-file> [workdir]

# 3) 小偏差返工：续接上次会话定向修复（注意：同一问题最多连续 --resume 2 次，超限请回退并开新会话）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --resume <session-id> --effort xhigh <rework-file> [workdir]

# 4) 编码后（慢层/高风险改动按需调用）：开启独立干净会话做只读代码复审（写审分离）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --code-review --effort xhigh <task-or-design-file> [workdir]

# 5) 敏感仓库安全实现模式（限制在工作区写入）
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --safe --effort xhigh <task-file> [workdir]
```

> **推理强度分级约定（每次显式传 `--effort`，不假设本地默认值）**：
> * 常规实现、常规升级、常规设计/代码 Review：`--effort xhigh`
> * 复杂架构 Review、慢层高爆炸半径改造、疑难并发 Bug：`--effort max`

### 2. 进入新代码仓库时的最佳实践
1. 用 `templates/AGENTS.md.template` 在仓库根目录建立一页以内的 `AGENTS.md`，写清模块数据归属、行为评估命令、核心不变量与关键决策溯源。
2. 中大型或慢层需求先用 `/plan` 或 `/grill-me` 问清模糊点（消除第一层 Gap），落成短设计稿后跑 `--review`；权衡裁剪后把不做项写入 `Non-Goals`、否决理由留痕设计稿，按“骨架先通、再填细节”拆单派发。
3. 无人值守长任务使用 `/goal`，确保在所有行为评估全部通过前不提前中止。

---

## 五、避坑与版本演进记录

1. **不要再配置旧版 `codex mcp-server`**：OpenAI Codex CLI 自 `v0.154.0` 起已移除该子命令。
2. **不要再用 `--full-auto`**：已弃用，请显式使用 `--sandbox workspace-write` 或 `--dangerously-bypass-approvals-and-sandbox`。
3. **不要把 `codex-executor` 放进 `~/.agents/skills/`**：放在 `~/.gemini/config/skills/` 可确保仅 Antigravity 可见。
4. **状态栏 `/compact` 刷新时机**：Antigravity CLI 执行 `/compact` 刚结束时，`context_window` 仍暂留压缩总结调用本身的用量，待发出下一轮对话消息触发新模型响应后会自动回落更新。

---

## 六、新 VM / 重装环境快速迁移清单

- [ ] 安装并登录 Codex CLI：`npm install -g @openai/codex && codex login`
- [ ] 克隆本仓库并执行 `./install.sh` 建立软链接
- [ ] 在 `~/.gemini/antigravity-cli/settings.json` 中按需启用 `statusLine`（参考 `examples/antigravity.settings.json.example`）
- [ ] 在 Antigravity CLI 中执行 `/config` 将权限预设设为 `Turbo`（或使用 `agy --dangerously-skip-permissions` 启动）
- [ ] 重启一次 `agy` 会话，验证 `codex --version` 正常输出即可投入使用
