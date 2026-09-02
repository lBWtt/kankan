# 项目协作约定

## Android 正式签名（发布前必读）

- Android 发布签名的 SSOT：`docs/ANDROID_RELEASE_SIGNING.md`。任何 release APK 构建、换机或交接前必须完整阅读。
- 千人以内内测的技术状态、备份、回滚和未完成外部事项：`docs/THOUSAND_BETA_READINESS_2026-08-16.md`；继续放量或接手生产前必须阅读。
- applicationId 固定为 `com.kankan.kankan_flutter`；正式证书 SHA-256 固定为 `23:10:D3:2B:28:4A:88:C4:F2:3B:45:4F:69:EE:DA:33:64:F7:00:C2:18:AA:DF:0F:A4:84:19:1C:69:E1:8B:2E`。
- 私钥只在仓库外 `%USERPROFILE%\.kankan-signing\`；不得提交、展示密码或重新生成替代密钥。
- release 缺少原密钥时必须停止，不得改回 debug 签名。
- release 必须显式使用 `USE_REMOTE=true` 与 `API_BASE_URL=https://lovluu.com/api/v1`；构建硬门不得删除或绕过。
- 唯一生产机是 `ubuntu@118.89.112.187`（`~/.ssh/kankan_tc`）；旧 IP `47.109.198.37` 永不连接。

## 小红书采集

- 使用可见的真实浏览器并复用用户本人已授权的登录会话。
- 采用低频、串行、自然间隔的搜索、翻页和滚动，不并发轰炸页面。
- 登录、短信、二维码或验证码必须由用户本人完成；程序不得绕过验证、风控或访问限制。
- 出现验证码、频率限制、异常跳转或账号风险提示时立即停止，保留现场并通知用户。
- 只采集完成当前内容筛选所必需的公开信息与成果图片，不抓取私密数据。
- 采集结果仍须经过全状态去重（包括已发布、已丢弃）和 DeepSeek 审核；人工助手不介入项目挑选。
