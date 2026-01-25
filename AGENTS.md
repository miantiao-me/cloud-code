# AI Agent 开发指南 (AGENTS.md)

## 项目概览
本项目是一个使用 Cloudflare Containers (支持 Docker 的 Workers) 的 Cloudflare Workers 项目。
项目完全使用 TypeScript 编写，并依赖 `wrangler` CLI 进行开发和部署。

**⚠️ 重要原则：本项目的官方语言为中文。所有的文档、注释、提交信息（Commit Messages）请务必使用中文。**

## 构建与开发命令

| 命令 | 说明 |
|------|------|
| `npm run dev` | 启动本地开发服务器 (`wrangler dev`) |
| `npm run start` | `npm run dev` 的别名 |
| `npm run deploy` | 部署到 Cloudflare (`wrangler deploy`) |
| `npm run cf-typegen` | 生成 Cloudflare Bindings 的类型定义 (`wrangler types`) |

> **关于测试**: 目前仓库中**没有任何测试框架或测试套件**。
> 请勿尝试运行测试。如果任务要求添加测试，请建议使用 **Vitest**。

## 代码风格与规范

### 格式化 (Formatting)
- **缩进**: 2 个空格。
- **分号**: 语句末尾**不使用**分号 (ASI)。
- **引号**: 字符串使用单引号 `'`。
- **尾随逗号**: 在有效的地方使用尾随逗号 (ES2017+)。

### 命名规范
- **文件名**: `camelCase` (小驼峰)，例如 `container.ts`, `sse.ts`, `index.ts`。
- **变量与函数**: `camelCase` (小驼峰)，例如 `verifyBasicAuth`, `processSSEStream`。
- **类与组件**: `PascalCase` (大驼峰)，例如 `AgentContainer`。
- **接口与类型**: `PascalCase` (大驼峰)，例如 `SSEEvent`。
- **常量**: `UPPER_CASE` (全大写下划线)，例如 `PORT`, `SINGLETON_CONTAINER_ID`。

### TypeScript 与类型
- **严格模式**: 已启用 (`strict: true`)。尽可能避免使用 `any`。
- **导出模式**: `index.ts` 的默认导出应使用 `satisfies ExportedHandler<Cloudflare.Env>`。
- **环境变量**: 通过 `import { env } from 'cloudflare:workers'` 访问。

### 架构模式
- **Cloudflare 特性**:
  - 使用 `cloudflare:workers` 和 `@cloudflare/containers`。
  - `AgentContainer` 继承自 `Container`，用于处理 Durable Object/Container 逻辑。
- **错误处理**:
  - 对于预期的流程（如认证失败），优先返回 `null` 或特定的错误对象/Response，而不是抛出异常。
  - 对于外部 IO/解析（如 SSE 流处理），必须使用 `try-catch` 块。
- **注释**:
  - **必须使用中文**编写所有新的注释和文档。
  - 现有的英文注释在修改时建议翻译为中文。

### 导入顺序
1. 外部库 (`cloudflare:workers`, `@cloudflare/containers`)。
2. 本地内部模块 (`./container`, `./sse`)。

## Agent 行为准则
1. **无测试环境**: 由于没有测试，必须通过仔细的代码审查和类型检查 (`npm run cf-typegen`) 来验证更改。
2. **Wrangler 为准**: 认定 `wrangler` 配置文件和命令是 Bindings 和配置的唯一真理来源。
3. **异步/Await**: 确保 Promise 被正确处理。注意：某些后台任务（如 `watchContainer`）在特定生命周期钩子（如 `onStart`）中可能**故意不被 await**，以避免阻塞，但需确保有错误捕获。
