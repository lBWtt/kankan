# 看看 Android 正式签名：发布与交接 SSOT

> 这是 Android 发布签名的唯一交接文档。任何人或 AI 代理（包括 Claude/Codex）接手时，先读本文件，再构建 APK。

## 1. 不可改变的发布身份

- applicationId：`com.kankan.kankan_flutter`
- 正式密钥别名：`kankan-release`
- 正式证书 SHA-256：`23:10:D3:2B:28:4A:88:C4:F2:3B:45:4F:69:EE:DA:33:64:F7:00:C2:18:AA:DF:0F:A4:84:19:1C:69:E1:8B:2E`
- 首个正式签名内测版本：`0.2.2+3`
- 创建日期：2026-08-14

`applicationId` 和签名证书共同决定 Android 眼中的 App 身份。不得重新生成密钥、不得换 alias、不得把 release 改回 debug 签名。密钥遗失时停止发布并联系项目所有者，不能“再生成一个试试”。

## 2. 密钥存放（绝不进 Git）

当前 Windows 开发机的私密目录：

```text
%USERPROFILE%\.kankan-signing\
├── kankan-release.jks
├── signing.properties
├── RECOVERY.txt
└── kankan-release-certificate.pem
```

- `kankan-release.jks`：私钥库，所有未来网站 APK 更新都必须使用它。
- `signing.properties`：本机构建读取的路径、alias 和密码。
- `RECOVERY.txt`：给项目所有者存入密码管理器的恢复信息。
- `kankan-release-certificate.pem`：仅含公钥证书，可用于核对身份。

目录 ACL 只允许当前 Windows 用户和 SYSTEM。仓库 `.gitignore` 同时拒绝 `*.jks`、`*.keystore`、`key.properties` 和 `signing.properties`。

换电脑时，安全复制**同一套**私密文件到新电脑的 `%USERPROFILE%\.kankan-signing\`。也可设置环境变量 `KANKAN_SIGNING_PROPERTIES`，让它指向迁移后的 `signing.properties`。不要把密码写进本文件、`CLAUDE.md`、Git、聊天或部署日志。

## 3. 固定构建命令

在 Windows PowerShell 中：

```powershell
cd F:\kankan\frontend
flutter pub get
flutter build apk --release `
  --dart-define=USE_REMOTE=true `
  --dart-define=API_BASE_URL=https://lovluu.com/api/v1
```

产物：

```text
F:\kankan\frontend\build\app\outputs\flutter-apk\app-release.apk
```

构建逻辑位于 `frontend/android/app/build.gradle.kts`：

- debug 构建不要求正式密钥；
- release 构建自动读取仓库外的 `signing.properties`；
- release 找不到原密钥时必须硬失败；
- 禁止回退到 Android debug keystore；
- release 构建还必须同时显式传入 `USE_REMOTE=true` 与
  `API_BASE_URL=https://lovluu.com/api/v1`，缺失或指向其他地址时硬失败。

## 4. 每次发布前验证

1. `frontend/pubspec.yaml` 的 `versionCode`（`+` 后数字）必须比网站上一个版本大。
2. API 地址必须是 `https://lovluu.com/api/v1`，不能是 `127.0.0.1`。
3. 核对 APK 的签名证书 SHA-256 必须等于第 1 节记录的值。
4. 在已安装上一个**正式签名版**的 Android 手机上直接覆盖安装，确认无需卸载。
5. 启动后检查项目流、登录、点赞、收藏和详情页。
6. 计算并记录 APK SHA-256，再替换网站下载包。

可用 `keytool` 查看本机固定证书（命令需要读取私密 properties，因此不要把输出中的其他信息贴到公开日志）：

```powershell
$dir = Join-Path $env:USERPROFILE '.kankan-signing'
$p = ConvertFrom-StringData (Get-Content (Join-Path $dir 'signing.properties') -Raw)
keytool -list -v -storetype PKCS12 `
  -keystore (Join-Path $dir $p.storeFile) `
  -storepass $p.storePassword -alias $p.keyAlias |
  Select-String 'SHA256:'
```

## 5. 网站 APK 部署

唯一生产服务器：

```text
ubuntu@118.89.112.187
SSH key: ~/.ssh/kankan_tc
```

`47.109.198.37` 是已经回收的旧 IP，永远不得连接。

生产下载入口（符号链接，保持不变）：

```text
/home/ubuntu/kankan/backend/deploy/webroot/downloads/kankan-android.apk
```

它固定指向实际 APK：

```text
/home/ubuntu/kankan/backend/deploy/webroot/kankan-client.apk
```

替换实际 APK 前先在服务器同目录保留带版本号的备份，不要删除或改写下载入口符号链接；上传后分别计算本地、服务器和公网回下载文件的 SHA-256，必须完全一致。此操作不需要重建后端或修改 Android 业务代码。

`0.2.2+3` 已于 2026-08-14 发布，APK SHA-256 为 `63BCDECE6AEC4F9BEB05D79C56F2D65CA1DC6525AC641483B0E70D55CEDB8DD1`。旧包保存在生产机的 `webroot/kankan-client-0.2.1-debug-signed.apk`。

`0.2.3+4` 已于 2026-08-16 发布，APK SHA-256 为
`35525BEEB7E2B5AC38D6DFD8DD326C2FBB9BE87DD207EFCF2CF0B0D73F2A4F69`。
生产下载入口仍是原符号链接；被替换的正式签名 `0.2.2+3` 保存在生产机的
`webroot/kankan-client-0.2.2+3.apk`。本版本仍使用第 1 节记录的同一证书，
`applicationId` 未改变，因此从 `0.2.2+3` 可以覆盖升级。

## 6. 从旧 debug 内测版迁移

网站此前的 `0.2.1+2` 使用 Android debug key 签名，不能直接覆盖升级到新的正式签名版。已经安装旧版的少量内测用户需要执行一次：

1. 确认账号数据已经在服务器；
2. 卸载旧 `0.2.1`；
3. 安装正式签名的 `0.2.2`；
4. 重新登录。

从 `0.2.2+3` 开始，只要一直使用本文件记录的正式密钥并递增 versionCode，后续版本即可直接覆盖升级。

## 7. Claude/Codex 接手检查表

- 先读本文件，不凭聊天记忆操作。
- 不展示、复制或重新生成私钥密码。
- 不修改 `applicationId`。
- 不把 `signingConfig` 指向 `debug`。
- 不因本机缺密钥而创建新 keystore；应要求项目所有者迁移原密钥。
- 构建后核对固定证书 SHA-256。
- 未完成覆盖升级测试前，不替换生产 APK。
