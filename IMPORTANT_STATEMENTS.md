# 系统架构披露

## 技能包来源追溯 (Skill Provenance)

| 属性 | 说明 |
|------|------|
| **技能仓 (Skill Repo URL)** | `https://github.com/Yeepay-Open-Platform/yeeap-wallet` |
| **安装方式** | `npx -y skills add "https://github.com/Yeepay-Open-Platform/yeeap-wallet" --agent '*' -g -y` |
| **审计状态** | 由易宝 YEEAP 团队维护 |

---

## CLI 依赖追溯 (CLI Provenance)

本技能唯一运行时依赖为 Go 二进制 **`yeeap-cli`**。首次缺失时，安装器从本 Skill 同一 GitHub 仓的 Release 下载对应平台二进制并验证 SHA-256；正常支付不依赖 npm、npx 或 Node。

| 属性 | 说明 |
|------|------|
| **二进制发布源** | [`Yeepay-Open-Platform/yeeap-wallet Releases`](https://github.com/Yeepay-Open-Platform/yeeap-wallet/releases) |
| **安装方式** | `install.sh` 下载对应平台包并校验 `checksums.txt` |

---

## CLI 鉴权原理 (Authentication Flow)

yeeap-cli 鉴权采用**一次性短效会话令牌 + 服务端签权**模型，全程无需用户提供支付密码或私钥：

1. **令牌获取**：`auth-init-context` 命令调用 Open API 服务端，生成一次性短效授权令牌（有效期通常 5 分钟），通过授权链接返回给用户。
2. **用户确认**：用户扫码或点击链接完成授权后，服务端将令牌标记为已授权。
3. **令牌验证**：`pay-context` 命令在提交支付时携带该令牌，服务端校验令牌有效性及授权范围后完成支付。
4. **凭据落盘**：`pay-context` 提交支付成功或命中服务端 SUCCESS 幂等路径后，服务端返回 `payCredential`，由 CLI 写入 `~/.yeeap/orders/<app_id>/<order_no>.json`；`pay-query` 不返回凭证。

**安全边界：**
- CLI **不**读取 `.env`、配置文件或环境变量中的任何私钥。
- CLI **不**要求用户提供支付密码。
- 授权令牌**一次性有效**，用完即废。
- 严格支付/授权命令必须使用 CLI 支付上下文模式；只允许使用 `pay-context`、`auth-init-context`、`check-auth-context` 与 `pay-query`；禁止使用旧版 `pay`、`auth-init`、`check-auth --strict` 流程；不得使用其他 Agent 留下的 pending auth 或 token 作为真实支付身份。
- `payCredential` 写回本地订单文件由 CLI 自主完成，Agent 不得通过 Read 工具直接读取原文对外展示。

---

## CLI 行为与安全流转 (Runtime Behavior)

| 命令 | 行为 |
|------|------|
| `pay-context` | 检查本地订单文件 → 查询远程订单状态 → 检测是否需要授权 → 提交支付 → 写回 `payCredential` |
| `auth-init-context` | 向服务端请求一次性授权链接，返回授权 URL 与 `auth_id` |
| `check-auth-context` | 查询 `auth_id` 对应的授权状态（processing / successful / failed） |
| `pay-query` | 仅查询订单状态，不返回也不写回 `payCredential` |

---

## 出站网络 (Egress)

| 目的地 | 用途 |
|--------|------|
| `github.com` / `api.github.com` | 首次安装时下载和校验 `yeeap-cli` Release |
| `ap.yeepay.com/yeeap` | 支付下单、授权、查询（Open API） |

---

## 调用策略与触发保护

- 仅在 **Phase 2 支付**、用户明确支付/授权指令、或业务 Skill 传入 `order_no` + `app_id` 时触发。
- 严禁在无支付意图时执行 `pay-context` 或向下单接口发请求。
- 展示授权 URL 后 **禁止自动轮询**；须等用户确认后再 `check-auth-context`。
- `pay-context` 与 `auth-init-context` 的授权 URL 须向用户展示并**等待人类确认**，不得轮询。

---

## 敏感数据处理

- Agent **不得**用 Read 工具打开订单 JSON 或 token 文件全文对外展示。
- `payCredential` 写回订单文件由 CLI 完成；对用户仅说明「已写入本地订单文件」。
- 展示授权链接或日志原文时，可将其中用于会话的查询参数（如 token、sign 等）简写为 `***`。
