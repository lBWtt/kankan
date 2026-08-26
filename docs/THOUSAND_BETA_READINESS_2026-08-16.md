# 看看千人以内 Android 内测技术交接

日期：2026-08-16  
结论：**已具备分批、受控地扩大到 1000 名以内测试用户的技术条件。**
这里的“1000 名”是累计受邀规模，不等于已验证 1000 人同时并发下载或请求。
建议按 `50 → 200 → 1000` 分批放量，每批先观察错误、登录短信和服务器资源。

## 1. 本次边界

- 未修改包名：`com.kankan.kankan_flutter`。
- 未更换正式签名证书。
- 未修改内容发现、采集、DeepSeek 整理、评分或审核台内容管线。
- 未修改点赞、收藏、项目流等既有产品语义。
- 只补齐内测前的发布硬门、隐私选择、账号注销、令牌安全、备份、日志与回滚能力。

## 2. 客户端已完成

- 版本提升为 `0.2.3+4`，生产 APK 已发布到原下载入口。
- release 构建必须带 `USE_REMOTE=true` 且 API 必须是
  `https://lovluu.com/api/v1`；漏传或写错会直接构建失败。
- Android release 仍使用固定证书；没有密钥时构建硬失败，不回退 debug 签名。
- Android 禁用系统自动备份，降低身份令牌随设备备份外流的风险。
- 原先存于普通偏好设置的移动端 token 自动迁移到 Android Keystore / iOS Keychain
  支持的安全存储；Web 端继续保留浏览器 30 天登录逻辑。
- 首次启动先让用户选择是否允许可选匿名分析；拒绝不影响浏览、登录、点赞和收藏，
  设置页可随时改变选择。
- 设置页增加账号注销：要求输入“注销”二次确认；管理员账号不能在客户端误删。
- 隐私政策、用户协议、反馈版本号和设置页版本号与当前行为、版本一致。
- 首次隐私选择与产品引导顺序已在干净安装环境验证，引导不会重复弹出。

## 3. 服务端已完成

- `DELETE /api/v1/me` 已上线。
- 注销会删除私密/行为数据，匿名化需要保留的审计关系，公开作品归到匿名墓碑账号，
  释放原手机号和邮箱，并撤销该用户所有设备的 refresh token。
- Redis 撤销失败时注销事务不会提交，避免“账号已删但旧会话仍可用”。
- 生产 PostgreSQL 每天自动备份并校验，保留 30 天。
- 生产 uploads 每周自动备份并用 zstd 校验，保留约三周。
- 四个生产容器均启用 `json-file` 日志轮转：单文件 10 MB，最多 5 个。
- 数据库、Redis 和后端容器重建后均恢复健康，公开项目流、落地页、Web App、审核台
  和 APK 下载入口均可访问。

## 4. 2026-08-16 验证证据

### 自动测试

- Flutter：`300/300` 通过。
- 后端规则单测：`37/37` 通过。
- Flutter analyze：`0 error`；仅剩 `project_card.dart` 中 2 个既有 warning，
  与本次改动无关。
- 未带生产 dart-defines 的 release 构建按预期硬失败；正确参数的 release 构建成功。

### 真机形态回归

- Pixel 3a / Android 13 干净安装验证：隐私选择、产品引导、重启、真实生产项目卡片和图片正常。
- 启动日志未发现 App 自身 fatal、ANR、FlutterError 或未捕获异步错误。
- 点赞、收藏等既有路径未改代码；本次没有真实短信号码，未做真实 OTP 与多账号写操作冒烟。

### 生产验证

- 注销接口用一次性测试账号完成端到端验证：HTTP 200、PII 清除、私密行为删除、
  分析事件解绑、公开作品保留、旧 refresh token 返回 401；测试数据已清理。
- 公开低风险压力检查：400 次请求、并发 20，400 次成功、0 失败，约 12.54 RPS；
  检查后后端健康，内存约 88 MiB。
- 当前数据库、Redis、后端健康；日志轮转参数已从运行中容器核对。
- APK 服务器文件与本地 SHA-256 一致；公网首尾各 1 MiB Range 哈希也一致。

## 5. 当前正式发布物

```text
versionName: 0.2.3
versionCode: 4
applicationId: com.kankan.kankan_flutter
APK bytes: 66391162
APK SHA-256: 35525BEEB7E2B5AC38D6DFD8DD326C2FBB9BE87DD207EFCF2CF0B0D73F2A4F69
certificate SHA-256: 23:10:D3:2B:28:4A:88:C4:F2:3B:45:4F:69:EE:DA:33:64:F7:00:C2:18:AA:DF:0F:A4:84:19:1C:69:E1:8B:2E
download: https://lovluu.com/downloads/kankan-android.apk
```

本地 APK：`F:\kankan\frontend\build\app\outputs\flutter-apk\app-release.apk`

## 6. 生产备份与回滚

唯一生产机：`ubuntu@118.89.112.187`，密钥 `~/.ssh/kankan_tc`。
`47.109.198.37` 是已回收旧 IP，永不连接。

本次人工 checkpoint：

```text
/home/ubuntu/kankan/backups/postgres/pre-thousand-beta-20260816T115910Z.dump
/home/ubuntu/kankan/backups/code/pre-thousand-beta-20260816/
```

自动备份：

```text
/home/ubuntu/kankan/backups/postgres/daily-*.dump
/home/ubuntu/kankan/backups/media/weekly-*.tar.zst
```

APK 回滚包：

```text
/home/ubuntu/kankan/backend/deploy/webroot/kankan-client-0.2.2+3.apk
```

回滚原则：先停止放量；应用层问题优先恢复上一 APK/后端代码；数据问题必须先保留现场，
再从已验证的 PostgreSQL 备份恢复。不要删除当前数据卷，也不要重新生成 Android 密钥。

## 7. 仍需项目所有者完成的外部事项

这些不是代码缺陷，也不能由仓库测试替代：

- 用真实手机号完成一次“发短信 → 登录 → 重启仍登录 → 退出”的冒烟，并确认短信余额、
  模板和每日额度能覆盖计划邀请量。
- 国内应用商店公开上架前，按目标商店要求完成 App 备案、软著/主体材料、隐私合规自查
  和审核；主体名称必须与营业执照逐字一致。
- 当前公网下载速度不足以证明能承受 1000 人同一时刻集中下载。首轮必须分批；若准备公开
  大规模投放，先把 APK 放到腾讯云 COS/CDN，再做下载峰值测试。
- 观察每批的错误率、短信成功率、服务器磁盘/CPU/内存和真实反馈；前一批异常时停止扩量。

## 8. Claude / Codex 接手顺序

1. 先读本文件和 `docs/ANDROID_RELEASE_SIGNING.md`。
2. 不更改包名、签名、生产 IP 或 APK 下载符号链接。
3. 构建时使用固定 production dart-defines，并核对证书与 APK SHA-256。
4. 修改生产前先做 DB/代码 checkpoint；修改后做健康、公开项目、登录与下载回归。
5. 内容管线是独立工作流；本交接不授权调整采集、DeepSeek、评分或审核规则。
