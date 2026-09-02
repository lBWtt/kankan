# 看看 · 旧部署草稿（不要直接用于当前生产）

> 当前生产部署 SSOT 是 `docs/deploy-steps.md`：唯一生产机为腾讯云上海 `ubuntu@118.89.112.187`。旧阿里云 IP 已回收，任何代理不得按本草稿连接旧机器。Android APK 发布必须另读 `docs/ANDROID_RELEASE_SIGNING.md`。

从买服务器到 iPhone 能公网访问，一步步照做。全程在 **`backend/` 目录**里操作。

> 架构：一台 ECS 上用 Docker 跑 4 个容器 —— **nginx**（唯一对外，80/443）+ **backend**（FastAPI，仅本机）+ **postgres** + **redis**。
> nginx 同时托管 Flutter web 静态包、把 `/api` `/uploads` 反代给后端 → 前后端**同源、零跨域**。iPhone Safari 打开公网地址即用。

---

## 0. 你要先准备的（花钱/账号部分）
- **阿里云 ECS**：最低 2核4G、Ubuntu 22.04 够用。**安全组入方向放行 80、443**（要直接调试后端可另放 8000，非必需）。
- （可选）**域名**：备案后解析到 ECS 公网 IP。没有域名先用 IP 也能跑（HTTP）。
- （可选）**OSS**：对象存储 bucket + AccessKey（媒体存 OSS，不占服务器盘）。不配则用本机盘。
- （可选）**阿里云短信**：签名 + 模板 + AccessKey。**不配的话验证码只写日志，真实用户登录不了**——iPhone 真用户要用，就得配。
- **DeepSeek API Key**：AI 整理用（放进 `.env.prod`，不进 git）。

## 1. 服务器装 Docker
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
```

## 2. 把代码弄上服务器
```bash
git clone <你的仓库地址> kankan && cd kankan/backend
# 或本地 scp 整个 kankan 目录上去
```

## 3. 本地编 Flutter web，上传到服务器
web 用**相对地址** `/api/v1`（同源，换 IP/域名都不用重编）。在**你的 Windows 开发机**上：
```powershell
cd F:\kankan\frontend
flutter build web --release --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=/api/v1
```
把产物 `frontend/build/web/` 整个上传到服务器的 `kankan/frontend/build/web/`
（compose 默认挂这个路径；也可在 `.env.prod` 里用 `WEB_ROOT=/绝对/路径` 指到别处）。

## 4. 配 `.env.prod`（在 backend/ 下）
```bash
cp .env.example .env.prod
```
按需填（`.env.prod` 已被 gitignore，密钥不会进仓库）：
```ini
# —— 必填 ——
POSTGRES_PASSWORD=换成强随机
JWT_SECRET=换成强随机（openssl rand -hex 32）
APP_ENV=prod

# —— AI 整理（你用 deepseek）——
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=sk-你的key
# 成本护栏：每日调用上限 + 定时整理（上线建议开）
AI_DAILY_CALL_CAP=500
INGEST_SCHEDULER_ENABLED=true
INGEST_INTERVAL_MINUTES=30

# —— 存储：默认本机盘；用 OSS 就填下面并把 STORAGE_BACKEND 改 s3 ——
STORAGE_BACKEND=local
# STORAGE_BACKEND=s3
# S3_ENDPOINT_URL=https://oss-cn-hangzhou.aliyuncs.com
# S3_BUCKET=你的bucket
# S3_ACCESS_KEY_ID=...
# S3_SECRET_ACCESS_KEY=...
# S3_REGION=oss-cn-hangzhou
# S3_PUBLIC_BASE_URL=https://你的bucket.oss-cn-hangzhou.aliyuncs.com

# —— 短信（真实用户登录要配；不配则登录不了）——
# SMS_PROVIDER=aliyun
# ALIYUN_SMS_ACCESS_KEY_ID=...
# ALIYUN_SMS_ACCESS_KEY_SECRET=...
# ALIYUN_SMS_SIGN_NAME=...
# ALIYUN_SMS_TEMPLATE_CODE=...
```

## 5. 起服务（会自动建表 alembic upgrade head）
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml ps          # 4 个容器都 healthy
docker compose -f docker-compose.prod.yml logs -f backend   # 看启动日志
```

## 6. （可选）灌点演示数据 + 头像
```bash
docker exec -it ccpj_backend python seed_dev.py
docker exec -it ccpj_backend python seed_avatars.py
```

## 7. 验证
```bash
curl http://127.0.0.1:8000/health                 # 服务器本机：后端活着
curl http://<ECS公网IP>/api/v1/topics?limit=1     # 外网：经 nginx 反代通
```
浏览器/手机开 `http://<ECS公网IP>` → 能看到「看看」首页即成功。

## 8. iPhone 上当 app 用
Safari 打开 `http://<ECS公网IP>`（配了域名+HTTPS 就用 `https://域名`）→ 分享按钮 → **添加到主屏幕** → 图标就在桌面，点开全屏、无浏览器地址栏，跟原生 app 体感接近（已配 PWA：名称「看看」、品牌色、独立显示）。

## 9. （可选）域名 + HTTPS
1. 域名解析到 ECS IP（备案后）。
2. 证书：阿里云免费 SSL 或 `certbot` 签，放到 `backend/deploy/certs/`（`fullchain.pem` / `privkey.pem`）。
3. 打开 `deploy/nginx.conf` 尾部的 443 段（把 `your-domain.com` 换成你的域名），compose 里 nginx 解开 `443:443` 和 certs 挂载，`up -d` 重启。
> HTTPS 后：iPhone「添加到主屏」体验更完整；真上架 App Store 的原生版也必须 HTTPS。

## 10. 日常运维
- **采集入库→整理**（定时调度开了就自动整理；手动补跑）：
  ```bash
  docker exec -it ccpj_backend python -m app.pipeline collect --file items.json --platform xiaohongshu
  docker exec -it ccpj_backend python -m app.pipeline process
  ```
- **更新版本**：`git pull` → 本地重编 web 上传 → `docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build`。
- **备份**：定期备份 `pgdata`、`uploads`（用 OSS 则媒体已在云上）。

---

## 后续：iPhone 原生 app（App Store）
网页版是现在的最优解。真要上架原生 iOS：需 **Mac + Xcode**（编包）+ **Apple 开发者账号（$99/年）**（TestFlight 内测 / App Store 上架）。可用云端 Mac（Codemagic 等）编，但仍需开发者账号。安卓原生已就绪（`flutter build apk --release`）。
