---
name: codex-executor
description: >-
  Use this skill when delegating codebase-grounded design reviews or concrete
  code implementation, refactoring, unit testing, and bug-fixing tasks to
  OpenAI Codex CLI while Antigravity acts as the project orchestrator,
  architect, and final reviewer.
---

# Codex 协作、设计审查与任务派发 SOP（方案 A）

本 Skill 用于在“Antigravity 统筹设计 + Codex 审查/落地”的模式下，利用 Codex 对代码仓库分析严谨、幻觉少的优势做设计把关，并以可控、可审计的方式派发实现任务与完成验收闭环。

## 1. 准备共享上下文（首次进入项目时）

在向某个代码仓库首次派单前，检查仓库根目录是否存在 `AGENTS.md`：
- `AGENTS.md` 会被 Antigravity 和 Codex 共同读取，应记录项目目录结构、技术栈、构建/测试命令和编码约定。
- 若项目尚未建立 `AGENTS.md` 且属于多步骤开发任务，先创建一份精简版，减少 Codex 走弯路。

## 2. 设计方案前置 Review 与架构权衡（中大型/复杂改动必做）

在完成架构/设计方案文档（如 `docs/design/<feature>.md`）后、正式拆分实现任务前，先交由 Codex 做**只读设计 Review**：

```bash
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh --review <design-doc> [workdir]
```

- `--review` 模式强制使用 `--sandbox read-only`，仅审查不改代码，重点请 Codex 对照真实代码库核查：事实偏差、现有接口/依赖冲突、遗漏调用点与潜在边界风险，并标出每条问题的严重级别与实现复杂度代价。
- **架构权衡（绝不盲目照单全收）**：
  Codex 容易对极端临界情况提出大量防御式编程建议。读完 `REPORT_FILE` 后，必须按以下三档逐条裁决：
  1. **必改项（Adopt）**：事实性错误、与现有代码冲突、主路径 Bug、安全或数据一致性隐患 → 直接修订设计方案。
  2. **审慎权衡项（Trade-off）**：极端临界条件或防御式兜底 → 权衡“发生概率与后果” vs “代码复杂度暴涨、可读性与可维护性下降”；代价过高时优先通过清晰的接口契约/前置假设约束，而非堆砌防御逻辑。
  3. **明确驳回项（Reject → 写入 Non-Goals）**：得不偿失的过度防御建议 → 不采纳，并在后续实现任务单的 **Non-Goals / 明确不做** 中写明取舍理由，防止 Codex 在写代码时自行补回防御逻辑。

## 3. 编写原子任务单

将单个可独立验收的任务写入 Markdown 文件：
- 默认放在当前项目的 `docs/tasks/<task-id>.md`（若不想在仓库内留任务文件，可写到 `/tmp/codex-tasks/<task-id>.md`）。
- 任务单必须包含以下 5 个部分：
  1. **目标与背景**：要解决什么问题、做到什么程度。
  2. **修改范围**：允许修改/新增的文件路径，以及明确禁止触碰的文件或模块。
  3. **设计约束**：接口签名、数据结构、核心错误处理要求。
  4. **明确不做（Non-Goals）**：经设计 Review 权衡后决定不处理的极端边界，明确禁止过度防御式编程，保持代码简洁可维护。
  5. **验收标准**：必须给出可直接执行的命令（如 `pytest`、`npm test`、`go test ./...`、构建/lint 命令）。

## 4. 派发给 Codex 执行

调用配套脚本 [run-codex.sh](./scripts/run-codex.sh)：

```bash
bash ~/.gemini/config/skills/codex-executor/scripts/run-codex.sh <task-file> [workdir]
```

常用可选参数：
- `--review`：只读设计审查模式（使用 `--sandbox read-only`，不修改任何文件）。
- `--resume <session-id>`：基于上次输出中的 `session id:` 续接原会话做定向返工，无需重新全量扫描仓库。
- `--effort <low|medium|high|xhigh|max>`：每次派单按任务复杂度**显式指定** Codex 推理强度（不依赖本地默认配置）：
  - 常规实现、常规升级、常规设计 Review：`--effort xhigh`
  - 复杂架构 Review、高风险改造、疑难并发或底层 Bug：`--effort max`
  - 极小机械改动/快速冒烟验证时可临时降为 `--effort high` 或 `medium`
- `--safe`：实现模式下降级为 `--sandbox workspace-write`（默认使用 `--dangerously-bypass-approvals-and-sandbox`，适配可回退 VM 内的无人值守长任务）。
- `--model <model>`：为本次任务显式指定 Codex 模型。

执行建议：
- `codex exec` 属于耗时操作，调用 `run_command` 时设置合理的 `NotificationTimeoutSeconds`（如 180~300 秒），等待异步完成通知，不要循环轮询。
- 脚本会自动检测非 Git 目录并附加 `--skip-git-repo-check`。
- 若当前仍开启了 Antigravity 沙箱，该命令需要外网与 `~/.codex` 凭证，按沙箱外执行处理。

## 5. 强制审查与验收闭环

Codex 退出后，**必须依次完成以下步骤**，不得跳过：

1. **读取 Codex 执行报告**：查看脚本输出的 `REPORT_FILE` 路径对应的报告内容。
2. **审查真实改动**：运行 `git status` 与 `git diff`，核对：
   - 是否严格在任务单允许的范围内改动；
   - 实现逻辑是否符合架构与接口契约；
   - **是否引入了过度防御式编程或超出 Non-Goals 的冗余复杂度**（若代码臃肿难懂，要求精简）；
   - 是否残留调试代码、临时文件或误改配置。
3. **亲自运行验收命令**：独立跑一遍任务单中的测试、类型检查或构建命令。
4. **返工或收尾**：
   - 若验收未通过或代码质量不达标：将具体报错、diff 问题和修复要求追加到新任务单（或原任务单的“返工要求”节），再次派单给 Codex。
   - 若全部通过：向用户汇报本次交付内容、关键架构取舍、变更文件与验收结果，并推进下一个任务。
