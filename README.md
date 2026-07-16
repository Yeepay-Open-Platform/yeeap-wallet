# yeeap-wallet

> 易宝 YEEAP 钱包支付技能 —— 让 AI Agent 安全地发起 YEEAP 支付交易。

`yeeap-wallet` 是一个面向 AI Agent（目前只支持Cursor、WorkBuddy）的支付技能包。它将 YEEAP 钱包的支付、授权与查询能力封装为可被 Agent 调用的标准化工作流，并通过 `yeeap-cli` 与易宝 Open API 交互。

由易宝 YEEAP 团队官方维护。

---

## 目录

- [特性](#特性)
- [工作原理](#工作原理)
- [安装](#安装)
- [能力一览](#能力一览)
- [典型流程](#典型流程)
- [安全边界](#安全边界)
- [项目结构](#项目结构)
- [许可协议](#许可协议)

---

## 特性

- 🎯 **Agent 原生**：以 `SKILL.md` 声明触发条件与执行协议，Agent 按需自动调用，无需硬编码集成。
- 🔐 **人类确认（Human-in-the-loop）**：所有引发实际授权或支付的 URL 必须展示给用户并等待明确确认，**绝不轮询**。
- 🪙 **一次性短效令牌**：采用「一次性短效会话令牌 + 服务端签权」模型，全程**不索要支付密码或私钥**。
- 🧩 **凭证托管**：`payCredential` 由 CLI 自主写回本地订单文件，Agent 不得读取原文对外展示。
- 🔒 **版本锁定**：固定使用 `yeeap-cli@wallet-stable` 官方稳定版 dist-tag，不使用 `@latest`。
- 🧭 **结构化分流**：支付结果按「凭证获取 → 授权回退 → 状态路由」的优先级规则逐步处理，覆盖成功 / 处理中 / 失败 / 订单不存在等全部分支。

---

## 工作原理

```
业务技能 Phase 1                  yeeap-wallet 技能                     易宝 Open API
   │  写入订单文件                       │                                    │
   │  (~/.yeeap/orders/...)              │                                    │
   ├───────── order_no + app_id ────────►│                                    │
   │                                     │  yeeap-cli pay-context             │
   │                                     ├───────────────────────────────────►│
   │                                     │◄───────── 支付凭证 / 授权链接 ──────┤
   │                                     │                                    │
   │           回调：查询支付状态         │                                    │
   │◄────────────────────────────────────┤                                    │
   │  返回支付状态                        │                                    │
   ├────────────────────────────────────►│                                    │
```

- 业务技能在 Phase 1 创建订单并把详情写入 `~/.yeeap/orders/<app_id>/<order_no>.json`。
- 本技能只接收 `order_no` 与 `app_id`，透传给 `yeeap-cli`，由 CLI 完成支付上下文准备、提交与凭证写回。
- 支付结果通过回调调用方业务技能确认最终状态，再按协议分流。

---

## 安装

通过 [skills](https://www.npmjs.com/package/skills) CLI 一键安装到全局，并作用于所有 Agent：

```bash
npx -y skills add "https://github.com/Yeepay-Open-Platform/yeeap-wallet" --agent '*' -g -y
```

技能运行时唯一依赖为 npm 包 [`yeeap-cli`](https://www.npmjs.com/package/yeeap-cli)。首次发起支付或授权命令前，Agent 会先执行 `yeeap-cli --version`；仅在 CLI 缺失或校验失败时安装：

```bash
npm install -g yeeap-cli@wallet-stable
```

Preflight 之后的所有命令**直接调用 `yeeap-cli`**，不再使用 `npx`。

---

## 能力一览

| 命令 | 说明 |
|------|------|
| `yeeap-cli pay-context -o <order_no> -a <app_id>` | 提交支付，获取支付凭证或授权链接 |
| `yeeap-cli auth-init-context -a <app_id>` | 单独发起支付授权，返回授权 URL 与 `auth_id` |
| `yeeap-cli check-auth-context -i <auth_id> -a <app_id> -o <order_no>` | 查询授权状态（processing / successful / failed） |
| `yeeap-cli pay-query -o <order_no> -a <app_id>` | 仅查询订单状态，不返回也不写回凭证 |

> **必需参数**：`order_no`（商户订单号）、`app_id`（收款方应用标识）。两者均由调用方业务技能在 Phase 1 明确提供，本技能**不**自行读取订单文件、环境变量或历史日志补全。

---

## 典型流程

### 发起支付

1. **接收参数**：从业务技能获取 `order_no` 与 `app_id`。
2. **执行**：`yeeap-cli pay-context -o <order_no> -a <app_id>`。
3. **按优先级分流**（命中第一项即停止）：
   - `已获取到支付凭证` → 提取订单号，回调调用方确认状态，再按成功 / 处理中 / 失败路由。
   - `支付状态: 处理中` → 告知用户处理中，禁止重复发起支付。
   - `订单状态: 待授权` + `授权链接:` → 展示授权链接，等待用户回复「我已授权」。
   - `订单不存在` → 在授权已成功的前提下，允许对同一订单自动重提一次。
   - 网络 / 系统异常 → 报告错误并停止。

### 授权与确认

- 展示授权链接后**禁止自动轮询**，须等用户确认。
- 用户回复「我已授权」时，先 `check-auth-context` 查询授权状态，再根据结果决定是否重新发起支付。

### 查看 yeeap 钱包

当用户请求「查看我的 yeeap 钱包」「打开 yeeap 钱包」时，提供钱包入口：

👉 [打开 yeeap 钱包](https://ap.yeepay.com/yeeap/)

---

## 安全边界

- **不索要敏感凭据**：永不向用户索要支付密码或私钥，也不在日志中留存。
- **本地订单文件**：`~/.yeeap/orders/<app_id>/<order_no>.json` 仅由 CLI 读写，禁止用 Read 等通用工具读取原文对外展示。
- **禁止自行探测身份上下文**：不得执行 `env`、`printenv`、读取 shell profile / `.env` / Agent 配置来推断 `agentId` / `loginAccount`；不得手动设置 `AGENT_SESSION_ID` 等变量。身份缺失时只展示 CLI 错误并停止。
- **禁止复用旧身份**：不得使用其他 Agent 留下的 pending auth 或 token 作为真实支付身份；只允许使用 `pay-context`、`auth-init-context`、`check-auth-context` 与 `pay-query`。
- **链接脱敏**：展示授权链接或日志原文时，可将 token、sign 等会话查询参数简写为 `***`。
- **出站网络**：仅访问 `registry.npmjs.org`（安装/执行 CLI）与 `ap.yeepay.com/yeeap`（Open API）。

完整安全约束见 [IMPORTANT_STATEMENTS.md](IMPORTANT_STATEMENTS.md)。

---

## 项目结构

```
yeeap-wallet/
├── SKILL.md                 # 技能声明与执行协议（Agent 入口）
├── IMPORTANT_STATEMENTS.md  # 系统架构披露与安全流转说明
├── LICENSE                  # MIT
└── README.md                # 本文档
```

---

## 许可协议

[MIT License](LICENSE) © Yeepay
