# 看看 · 上线一步步操作手册

> 按 **"要等审核的先启动、能并行的并行"** 排好顺序，照阶段做就行。
> 服务器/部署细节见同目录 [`DEPLOY.md`](./DEPLOY.md)，本文是**带先后顺序的行动清单**。

## 🔴 关键提醒（先记住）
后端发短信时模板变量**写死是 `${code}`**（`backend/app/services/sms.py` → `TemplateParam={"code": code}`）。
你在阿里云建短信模板**必须**用 `${code}` 这个变量名，写成别的（如 `${verifyCode}`）就发不出去。

---

## 🔴 阶段 A（今天马上做，因为要等审核）

### A1. 提交阿里云短信「签名」+「模板」申请 —— 头号阻断，审核几小时~1 天，越早交越好
1. 阿里云控制台 → 搜「短信服务」→ 国内消息。
2. **签名**：签名管理 → 添加签名。
   - 名称：你的 App 名（如 `看看`）
   - 签名来源：「App 应用」
   - 场景说明：用于用户注册登录验证码
   - 提交，等审核。
3. **模板**：模板管理 → 添加模板。
   - 类型：**验证码**
   - 内容：`您的验证码是${code}，5分钟内有效，请勿泄露。`
   - ⚠️ **变量名必须是 `code`**，别用别的。
   - 提交，等审核。
4. **AccessKey**：用 RAM 用户（别用主账号）。
   - 访问控制 RAM → 创建用户 → 加权限 `AliyunDysmsFullAccess` → 生成 AccessKey ID / Secret，记下来。

> 审核通过后你会拿到：**签名名称**（SignName）、**模板 CODE**（TemplateCode，形如 `SMS_123456789`）。
> 这四样（签名、模板 CODE、AccessKey ID、Secret）填进 `.env.prod`。

### A2.（只有想要自定义域名 + HTTPS 才做）启动域名备案
备案最慢（几天~几周）。内测阶段可以先用 **ECS 公网 IP + HTTP**，不卡这条。要域名就现在去阿里云备案。

---

## 🟡 阶段 B（等审核时，并行搭服务器）—— 照 `DEPLOY.md` 走

不需要短信通过，先把站点跑起来（先用 IP、先不填短信）。

1. **买 ECS**：2核4G / Ubuntu 22.04，安全组入方向放行 **80、443**（`DEPLOY.md §0`）。
2. **装 Docker**：
   ```bash
   curl -fsSL https://get.docker.com | sh
   systemctl enable --now docker
   ```
3. **传代码**：`git clone` 到服务器（`§2`）。
4. **本地编 web 传上去**（在你 Windows 机）：
   ```powershell
   cd F:\kankan\frontend
   flutter build web --release --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=/api/v1
   ```
   把 `build/web/` 传到服务器对应目录（`§3`）。
5. **配 `.env.prod`**（`§4`）—— 这一份就顺手把 **"干掉 dev 万能码 + 审核台保护"** 一起 settle 了：
   ```ini
   APP_ENV=prod                          # ← 配上它 + 下面强 JWT，888888 万能码自动失效
   JWT_SECRET=<openssl rand -hex 32 生成>  # ← 强随机，令牌不可伪造
   POSTGRES_PASSWORD=<强随机>
   # 审核台：prod 默认已自动关（代码已改）；真要开才显式 ADMIN_WEB_ENABLED=1
   AI_PROVIDER=deepseek
   DEEPSEEK_API_KEY=sk-你的key
   SHARE_BASE_URL=http://<你的ECS公网IP>   # ← 阶段C换成真域名；先填 IP 别留占位（否则分享 404）
   STORAGE_BACKEND=local                  # ← 阶段D换 s3
   ```
6. **起服务**（自动建表）：
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
   ```
7. **验证**（`§7`）：
   ```bash
   curl http://<公网IP>/api/v1/topics?limit=1
   ```
   手机 Safari 开 `http://<公网IP>` 看到首页即成功。

> 到这一步：**站点公网能开、能浏览**了。但还不能注册（短信没配）——等阶段 A 审核过。

---

## 🟢 阶段 C（短信审核通过后，10 分钟收尾）

1. 编辑服务器上 `backend/.env.prod`，填 A1 拿到的四样：
   ```ini
   SMS_PROVIDER=aliyun
   ALIYUN_SMS_ACCESS_KEY_ID=...
   ALIYUN_SMS_ACCESS_KEY_SECRET=...
   ALIYUN_SMS_SIGN_NAME=看看
   ALIYUN_SMS_TEMPLATE_CODE=SMS_xxxxxxxx
   ```
2. 重启：
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
   ```
3. **真机验**：手机开站点 → 用**你自己的真实手机号** → 发验证码 → 看能不能收到短信 → 登录成功。
   > 收不到就看 `docker compose ... logs -f backend`，常见是"模板未审核 / 签名错 / 变量名不是 code"。

---

## 🔵 阶段 D（OSS，媒体别丢）—— 建议内测稳定后就切

> ⚠️ 留 `STORAGE_BACKEND=local` 时**生产自检不会拦启动**，媒体会继续写单机盘，换机/迁移就丢。必须**主动**切。

1. 阿里云 OSS → 创建 Bucket（读写权限设「公共读」，region 记下如 `oss-cn-hangzhou`）。
2. `.env.prod` 改：
   ```ini
   STORAGE_BACKEND=s3
   S3_ENDPOINT_URL=https://oss-cn-hangzhou.aliyuncs.com
   S3_BUCKET=你的bucket
   S3_ACCESS_KEY_ID=...          # 可复用 A1 的 RAM AccessKey，给它加 OSS 权限
   S3_SECRET_ACCESS_KEY=...
   S3_REGION=oss-cn-hangzhou
   S3_PUBLIC_BASE_URL=https://你的bucket.oss-cn-hangzhou.aliyuncs.com
   ```
3. 重启。之后审核通过的新媒体就进 OSS 了（旧的本地图可不迁，内测无所谓）。

---

## ⚙️ 那条 mock 审计 —— 是开发的活，不用你操作，也不卡上线
"登录 + 远端下 收藏 / 素材 / 贡献 / 最近看过 是否读后端"——这是**代码审计**，一屏屏查、小心改，不需要你在服务器上做什么。它**不阻断阶段 A–D 的上线**，可以搭服务器的同时并行推。

---

## ✅ 你现在只需要做一件事
**去阿里云把短信「签名 + 模板」申请交了**（阶段 A1）——因为它要等审核，是整条链路最长的一环。

## 📋 一句话总览
| 阶段 | 做什么 | 卡点 |
|---|---|---|
| A | 交短信签名+模板申请（+ 可选域名备案） | 等审核（几小时~1天） |
| B | 买 ECS、搭 Docker 四容器、配 prod .env、先用 IP 跑起来 | 无（可并行） |
| C | 短信过审后填 4 个值、重启、真机收码 | 依赖 A 审核 |
| D | 开 OSS、切 s3、重启 | 建议内测后 |
| mock 审计 | 开发侧改，不占你 | 不阻断上线 |
