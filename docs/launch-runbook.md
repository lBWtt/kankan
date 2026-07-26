# 看看 · 上线部署清单（阿里云）

> 目标：把后端跑到阿里云生产、App 指向生产、真短信能登录。
> 本文是**照单执行**版；`<尖括号>` 的地方换成你的真实值。

---

## 0. 前置（一次性）

云服务器上装好：
- Python 3.9+、pip、virtualenv（或 conda）
- PostgreSQL 15（或用阿里云 RDS）
- Redis（或用阿里云 Redis）
- Nginx（反代 + HTTPS）
- 阿里云 **OSS Bucket**（媒体存储）、**短信服务**（签名 + 模板，模板须含 `${code}`）

---

## 1. 拉代码 + 依赖

```bash
git clone <你的仓库> kankan && cd kankan/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## 2. 生产 `.env`（照 `.env.example` 填，重点这几项）

```ini
APP_ENV=prod
JWT_SECRET=<openssl rand -hex 32 生成的强随机值>     # 必改，否则拒绝启动
DATABASE_URL=postgresql+psycopg2://<用户>:<密码>@<RDS地址>:5432/<库>
REDIS_URL=redis://<redis地址>:6379/0
TRUSTED_PROXY_HOPS=1                                  # 有一层 nginx 就填 1

# 媒体 → 阿里云 OSS（S3 兼容）
STORAGE_BACKEND=s3
S3_ENDPOINT_URL=https://oss-cn-<region>.aliyuncs.com
S3_BUCKET=<你的bucket>
S3_ACCESS_KEY_ID=<AK>
S3_SECRET_ACCESS_KEY=<SK>
S3_REGION=cn-<region>
S3_PUBLIC_BASE_URL=https://<bucket>.oss-cn-<region>.aliyuncs.com   # 或 CDN 域名

# 短信 → 阿里云
SMS_PROVIDER=aliyun
ALIYUN_SMS_ACCESS_KEY_ID=<AK>
ALIYUN_SMS_ACCESS_KEY_SECRET=<SK>
ALIYUN_SMS_SIGN_NAME=<短信签名>
ALIYUN_SMS_TEMPLATE_CODE=<模板CODE，模板含 ${code}>

# 分享回流页域名
SHARE_BASE_URL=https://<你的域名>

# 审核台：生产默认不挂；要开务必配 IP 白名单/内网
ADMIN_WEB_ENABLED=0

# 采集/AI（可选，想自动供内容再开）
INGEST_SCHEDULER_ENABLED=true
AI_DAILY_CALL_CAP=500
AI_PROVIDER=claude            # 或 deepseek（用 deepseek 则填 DEEPSEEK_API_KEY，模型用 deepseek-v4-flash/pro）
ANTHROPIC_API_KEY=<key>
```

> 启动时有**生产自检**：JWT 还是默认值 / SMS 还是 console / OSS 没配全 → 直接拒绝启动，帮你挡致命脚印。

## 3. 建表（⚠️ 别漏，本地就踩过这个坑）

```bash
alembic upgrade head        # 把 schema 升到最新（缺这步：意见反馈等功能会 500）
```

## 4. 上数据（二选一）

### 路径 A（推荐，最快）：把本机这套库整个搬上去
本机库已有 200 马甲 + 108 项目 + 全部互动，直接搬，省去在生产重新采集/灌种子。
```bash
# 本机导出（排除大对象即可，媒体走 OSS 另说）
pg_dump -h localhost -p 15432 -U ccpj -d ccpj -Fc -f kankan.dump
# 传到服务器后，在生产库恢复（先建空库）
pg_restore -h <RDS地址> -U <用户> -d <库> --no-owner kankan.dump
# 清测试足迹：删测试号、改派真实内容给马甲、删垃圾项目/动态/埋点（运营数据从 0 起）
python clean_test_data.py            # 先 dry-run 看清单
python clean_test_data.py --apply    # 确认无误再落库
```

### 路径 B：生产从零灌种子
```bash
python seed_personas.py                # 200 马甲（潜在人名 + 生活感签名）
python seed_persona_follows.py         # 互关（粉丝长尾 ≤200）
python seed_avatars.py --all           # 头像（猫/狗/风景/艺术/插画，抓开放图源）
DEEPSEEK_API_KEY=<key> DEEPSEEK_MODEL=deepseek-v4-flash python seed_persona_interactions.py  # 互动
# 已发布内容：跑采集+审核，或 python seed_dev.py
```

> DeepSeek key 只在命令行内联传，别写进 .env 提交。

### 设管理员（两条路径都要）
生产 dev 万能码已失效。**用你的真手机号在 App 登录一次**（自动建号），再：
```bash
python make_admin.py <你的手机号>      # 设为管理员，才能进审核台
```

## 5. 起服务

```bash
# gunicorn + uvicorn worker（示例 4 worker）
pip install gunicorn
gunicorn app.main:app -k uvicorn.workers.UvicornWorker -w 4 -b 127.0.0.1:8000
# 建议做成 systemd 服务常驻；nginx 反代 443 → 127.0.0.1:8000，配 HTTPS 证书
```

Nginx 要点：`proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`（配合 `TRUSTED_PROXY_HOPS=1`，IP 限流才准）。

## 6. 上线前自测（关键：真短信只有生产能测）

```bash
# 1) 服务起来了
curl https://<域名>/openapi.json -o /dev/null -w "%{http_code}\n"   # 200
# 2) 真手机号发验证码（⚠️ 最易翻车：签名没审过/模板错→全线登录失败）
curl -X POST https://<域名>/api/v1/auth/send-code \
  -H 'Content-Type: application/json' \
  -d '{"identifier_type":"phone","identifier":"<你的真手机号>"}'
# 收到短信 → 用收到的码登录 → 昵称/handle 自动生成 → 能浏览/发作品/收藏/关注/评论
```

## 7. 前端 release 包（指向生产）

```bash
cd ../frontend
flutter build apk --release \
  --dart-define=USE_REMOTE=true \
  --dart-define=API_BASE_URL=https://<域名>/api/v1
# iOS 同理 flutter build ipa（App Store 审核另走流程）
# 审核台网页版（跟消费包隔离）：flutter build web --dart-define=ADMIN=true --dart-define=API_BASE_URL=...
```

## 8. 上线后
- 审核台 → 运营数据：盯真实用户/DAU（管理员活跃≈总活跃=还在自嗨）
- 审核台 → 意见反馈：看用户反馈
- 定期审核候选池，保证内容供给

---

## 常见坑
- **登录不上**：先查短信签名是否审过、模板是否含 `${code}`、AK 权限。`sms.py` 会把模板未审核报成"发送失败"。
- **图片全破**：OSS 没配全 / `S3_PUBLIC_BASE_URL` 域名错。
- **接口 500**：多半是 `alembic upgrade head` 没跑，或 DB/Redis 连不上。
- **IP 限流失真**：`TRUSTED_PROXY_HOPS` 与实际反代层数不符。
