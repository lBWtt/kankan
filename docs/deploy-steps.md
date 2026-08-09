# 看看 · 上线照着做（腾讯云上海 / 118.89.112.187 / lovluu.com 已备案）

> 你的环境：阿里云成都 ECS 2核4G，Ubuntu 22.04，Docker 已装，域名 `lovluu.com` 已 ICP 备案。
> 目标：后端跑到 `https://api.lovluu.com`，真短信能登录，App 指向它。
> `<尖括号>` 换成你的真实值。命令直接粘进服务器 shell。

---

## ① 拉代码
```bash
cd ~
git clone -b feat/media-transfer https://github.com/lBWtt/kankan.git
cd kankan/backend
```
> 提示要密码时用 **GitHub Personal Access Token** 当密码（github.com → Settings → Developer settings → Personal access tokens）。仓库公开则直接过。

## ② 配 `.env.prod`
```bash
cp .env.example .env.prod
echo "JWT_SECRET=$(openssl rand -hex 32)"        # 复制这行输出
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" # 复制这行输出
nano .env.prod
```
填这些（其余保持默认即可）：
```ini
APP_ENV=prod
JWT_SECRET=<上面生成的>
POSTGRES_PASSWORD=<上面生成的>

# 媒体 → 阿里云 OSS（成都）
STORAGE_BACKEND=s3
S3_ENDPOINT_URL=https://oss-cn-chengdu.aliyuncs.com
S3_BUCKET=<你的bucket>
S3_ACCESS_KEY_ID=<AK>
S3_SECRET_ACCESS_KEY=<SK>
S3_REGION=cn-chengdu
S3_PUBLIC_BASE_URL=https://<bucket>.oss-cn-chengdu.aliyuncs.com

# 短信 → 阿里云
SMS_PROVIDER=aliyun
ALIYUN_SMS_ACCESS_KEY_ID=<AK>
ALIYUN_SMS_ACCESS_KEY_SECRET=<SK>
ALIYUN_SMS_SIGN_NAME=<短信签名>
ALIYUN_SMS_TEMPLATE_CODE=<模板CODE，含 ${code}>

# 分享回流域名
SHARE_BASE_URL=https://lovluu.com

# 审核台（配合安全组只放行你的 IP，别全公网裸奔）
ADMIN_WEB_ENABLED=1

# AI（用 deepseek；key 别提交，写这里的 .env.prod 是本机文件不入库）
AI_PROVIDER=deepseek
DEEPSEEK_API_KEY=<你的key>
DEEPSEEK_MODEL=deepseek-v4-flash
AI_DAILY_CALL_CAP=500
```

## ③ 起服务（一条命令，四容器：backend + nginx + postgres + redis）
```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```
后端会自动 `alembic upgrade head` 建表。首次 build 拉依赖几分钟。

## ④ 本机验证
```bash
docker compose -f docker-compose.prod.yml ps          # 四个都 Up/healthy
curl -s http://127.0.0.1:8000/health                   # 后端直连 → ok
curl -s http://127.0.0.1/api/v1/projects?page_size=1   # 经 nginx → JSON
```

---

## ⑤ 上数据（迁移本机库，一次搞定 200 马甲 + 108 项目 + 全部互动）

**在你本机（Windows）**（本机 Postgres 在 Docker 15432）：
```powershell
docker exec ccpj_postgres pg_dump -U ccpj -Fc ccpj > kankan.dump
scp kankan.dump ubuntu@118.89.112.187:~/kankan/backend/
```
> 我已在本机 `F:\kankan\kankan.dump` 生成好一份，直接 scp 这个也行。

**回到服务器**：
```bash
cd ~/kankan/backend
docker compose -f docker-compose.prod.yml stop backend
docker cp kankan.dump ccpj_postgres_prod:/tmp/kankan.dump
docker exec ccpj_postgres_prod pg_restore -U ccpj -d ccpj --clean --if-exists --no-owner /tmp/kankan.dump
docker compose -f docker-compose.prod.yml start backend
# 清测试足迹（删测试号/改派内容给马甲/删垃圾/埋点归零）
docker exec -it ccpj_backend python clean_test_data.py            # 先看清单
docker exec -it ccpj_backend python clean_test_data.py --apply    # 确认后落库
```

## ⑥ 设你为管理员
生产 dev 万能码已失效。**先用你的真手机号在 App 或 `https://api.lovluu.com/admin-web/` 登录一次**（自动建号），再：
```bash
docker exec -it ccpj_backend python make_admin.py <你的手机号>
```

## ⑦ 域名 + HTTPS（已备案，走正规）
1. **DNS**：给 `lovluu.com` 加一条 A 记录 `api` → `118.89.112.187`。
2. **免费证书**：阿里云「数字证书管理服务 → 免费证书」申请 `api.lovluu.com`，签发后下载 **Nginx 格式**，得到 `fullchain.pem` + `privkey.pem`。
3. **放证书 + 开 HTTPS**：
```bash
mkdir -p ~/kankan/backend/deploy/certs
# 把两个 pem 传进 deploy/certs/（scp 或 nano 粘贴）
```
   - 编辑 `docker-compose.prod.yml`：解开 nginx 的 `- "443:443"` 和 `- ./deploy/certs:/etc/nginx/certs:ro` 两行注释。
   - 编辑 `deploy/nginx.conf`：解开文件尾的 443 server 段，把 `server_name` 改成 `api.lovluu.com`，并让 80 段 301 跳 443。
   - 安全组放行 **443**。
   - 重启：`docker compose -f docker-compose.prod.yml up -d`
4. 验证：`curl https://api.lovluu.com/api/v1/projects?page_size=1`

## ⑧ 上线前必测：真短信（只有生产能测）
```bash
curl -X POST https://api.lovluu.com/api/v1/auth/send-code \
  -H 'Content-Type: application/json' \
  -d '{"identifier_type":"phone","identifier":"<你的真手机号>"}'
```
收到短信 → 用码登录 → 昵称/handle 自动生成 → 能浏览/发作品/收藏/关注/评论。
> 收不到多半是：短信签名没审过 / 模板不含 `${code}` / AK 权限不足。

## ⑨ 出 App 正式包（指向生产）
在你本机 `frontend/` 下：
```bash
flutter build apk --release \
  --dart-define=USE_REMOTE=true \
  --dart-define=API_BASE_URL=https://api.lovluu.com/api/v1
```
装到手机测一遍全链路，没问题就分发 / 上架。

---

## 上线后
- `https://api.lovluu.com/admin-web/` → 审核台：审内容、**运营数据**（看真实用户/DAU）、**意见反馈**、改马甲。
- 盯：管理员活跃≈总活跃 = 还在自嗨；有真实用户进来数字才有意义。

## 常见坑
- **接口 500**：多半 DB/Redis 没起或 `alembic upgrade head` 没跑（Docker 里自动跑，除非 restore 打断——重启 backend 即可）。
- **图片破**：OSS 没配全 / `S3_PUBLIC_BASE_URL` 错。
- **登录收不到码**：短信签名/模板/AK 权限。
- **限流不准**：`TRUSTED_PROXY_HOPS` 与反代层数不符（compose 已默认 1，对应一层 nginx）。
