# 看看 · 后续路线图

> 汇总来源：9 轮深度审查（代码质量 / 技术债 / 数据库 / API 契约 / 模拟器运行时 / 导航 UX / 安全 / AI 管线 / Provider 架构）+ 联调实测。
> 生成日期：2026-07-10。优先级与成本是相对估计，按需调整。

---

## ✅ 已完成（近期）
- 接后端联调跑通：android 平台 + `network_security_config` 明文放行（仅 dev IP）+ `start_app` 走 `adb reverse`（绕开本机代理导致的模拟器网卡失效）
- 审查采纳修复：后端 `IntegrityError` 收窄 23505 / `import time` 提顶 / 迁移 0010 FK 索引；前端 `PlatformDispatcher.onError` / 裸 Dio close / 1px 溢出 / 路由守卫+登录回跳 / 404 兜底 / 搜索 push→replace / 远端跳过假骨架
- 安全：X-Forwarded-For 取值加固（`trusted_proxy_hops` + `core/net.py::client_ip`），防换头绕过 IP 限流刷短信
- 种子本地封面（无外网也显示，替代 picsum 外链）

---

## 🟢 Track A — 接全真数据（推荐先做）
> 目标：把还在 mock 兜底的地方换成真后端，让 app 端到端是真的。

| 任务 | 现状 | 后端端点 | 成本 | 备注 |
|---|---|---|---|---|
| **「我发布的」项目/动态** | 前端用 `projectRepo.byAuthor('me')`（mock） | ✅ `/users/{id}/projects`、`/users/{id}/posts` **已存在** | 小 | 只差前端换掉 mock，接真 → 发布后能在 me 页看到。**最快的一个** |
| me 页计数（关注/粉丝/获赞/收藏） | 登录后已是真值（新号显示 0） | ✅ `/users/{id}` | — | 基本已真，核对即可 |
| **贡献热力图** | mock（新号也显示 322） | ❌ 无聚合端点 | 中 | 需新建「按天贡献聚合」端点；新号会是空热力图（真但不好看，接受） |
| **动态搜索** | 搜索「动态」Tab 走本地 mock | ❌ `GET /posts` 无 `q` 搜索 | 中 | 需新建 posts 搜索端点；项目搜索已是真 |
| **领域/分类体系对齐** | 前端 `ai_image/web/app…` vs 后端 `dev/design/video…` | — | 中（跨端） | **兴趣设置现在接不通**就是因为这个；需统一一套枚举 + 迁移 + UI |
| 「最近看过」浏览历史 | 本地存储 | — | 低 | 优先级低，可留本地 |

**建议顺序**：我发布的（快）→ 领域对齐（解锁兴趣设置）→ 动态搜索 → 贡献热力图。

---

## 🔴 Track B — AI 抓取管线自动化（产品的灵魂）
> 现状：爬取→AI 精炼→人工审核→发布，**整条靠人手工跑 CLI**，无调度。产品承诺「每日新鲜」但全靠操作员记得跑。

- [ ] **定时调度**：APScheduler / 系统 cron / API 触发，替代手工 `python -m app.pipeline …`
- [ ] **成本护栏**：token 预算 / 单批限额 / 用量统计，避免恶意内容反复重试烧钱
- [ ] **Prompt 注入清洗**：爬取原文注入 Claude user message 前做分隔/净化（当前有人工审核闸兜底，优先级中）
- [ ] `transition_candidate` 加 `FOR UPDATE`（与 `approve_candidate` 对齐；现状最坏是重复审计日志）
- [ ] prompt / 模型版本记录（换模型可溯源）+ 人工淘汰反馈回流优化 prompt
- [ ] 种子加候选管线数据（admin 审核界面现在开箱是空的）

---

## 🟡 Track C — 上线级补全（真要部署才需要）
- [ ] 推送通知落地（`push-preferences` 已有，实际推送通道缺）
- [ ] 生产配置：S3 存储、阿里云短信、`SHARE_BASE_URL`、`JWT_SECRET` 强随机
- [ ] **Redis 设密码**（当前无认证）
- [ ] 限流对**发码 / 猜码**这类成本敏感路径改 fail-close（或加内存兜底）；通用限流保持 fail-open 可接受
- [ ] `trusted_proxy_hops` 按真实部署拓扑设（已加配置，上线记得填）

> 注：**「举报无后端」已过时** —— `/reports` 的 GET/POST/resolve 端点已存在，只差前端消费。

---

## 🟠 Track D — 架构还债（不急但迟早）
- [ ] **拆 `AppStateNotifier`**（1、3、9 轮**三次独立点名**的神级 Provider）：按切片拆成多个职责单一 provider，减少连锁重建
- [ ] 收敛全局可变状态（`backingProjects` / `_remoteUsers` 无淘汰 / `mockComments`）：测试隔离 + 防内存增长
- [ ] 补 smoke/单测：路由守卫、XFF 取值、`IntegrityError` 幂等路径、乐观更新回滚竞态
- [ ] `_refresh` 加重入锁（防快速双下拉互相覆盖）
- [ ] 预测性返回手势：manifest 加 `android:enableOnBackInvokedCallback="true"`（一行）
- [ ] 清理疑似死 provider（`remotePosts/Projects/Followers/Following`，确认无消费者后删）

---

## 🚫 明确不做（评估后判为误报 / 低价值，避免被重复提出）
- **迁移 0009 外键名「BUG」= 误报**：0001 用裸 `sa.ForeignKey` → PG 默认名，与 0009 一致；live DB 已在 0009 证明迁移成功。按审查建议改反而会造成**重复外键 + 原约束丢 ondelete**。
- **限流器 fail-open 定「Critical」过高**：对限流器是可辩护的可用性权衡；且发码路径后续 Redis 操作会 fail-close。仅成本敏感路径值得改（见 Track C）。
- **「登录无限流」= 假**：已有 IP 限流 + 猜码次数锁 + 常量时间比较。
- **状态机倒流「无校验」= 夸大**：`ensure_actionable` 校验源状态，目标由调用方写死。
- **`PaginatedState` 展开拷贝 O(n)**：feed 量级下开销可忽略。
- **模拟器帧率/内存「严重」**：debug + 模拟器软件 GPU 的正常表现，非 release 真机数据。
- **启动脚本硬编码路径**：solo 仓无所谓，多人/换机再参数化。

---

## 备注
- 模拟器联调固定用法：先 `start_backend.bat` → 起模拟器 → `start_app.bat`（自动 `adb reverse` + 连 `127.0.0.1`）。每次重启模拟器后 `adb reverse` 会失效，脚本每次会重设。
- 环境坑：本机 Clash 系统代理会搞挂模拟器虚拟网卡，故走 adb reverse + loopback 绕开，勿依赖 `10.0.2.2`。
