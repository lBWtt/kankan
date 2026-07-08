# 看看 / kankan —— AI 创意用例发现 App（前后端单库）

策展式 AI 创意用例发现与收藏工具——"看你这行的人用 AI 做了什么、且你能直接用上"。

## 目录结构

```
backend/    FastAPI + PostgreSQL 16 + Redis 7 + SQLAlchemy 2 + Alembic（原 backend-kankan）
frontend/   Flutter Web/App（原 kankan-flutter，即 flitter1）
```

两个子目录各自保留了合并前的完整 git 历史（subtree 合并）。运行说明见下方「快速起步」；
更细的后端约定见根目录 `CLAUDE.md`，前端见 `frontend/docs/KANKAN_SPEC.md`。

## 快速起步

```bash
# 后端（在 backend/ 下）
docker compose up -d                 # Postgres(15432) + Redis
alembic upgrade head                 # 建库，当前 head = 0009
python seed_dev.py                   # 种 6 条演示项目
uvicorn app.main:app --port 8000     # GET /health 应 200

# 前端（在 frontend/ 下）
flutter pub get
flutter run                          # 或 flutter build web --release --pwa-strategy=none
#   接后端真数据：--dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

## 上线前 TODO

- 媒体存储切 s3：后端 `.env` 设 `STORAGE_BACKEND=s3` + 填 `S3_*`（代码已就绪，见 `backend/app/services/storage.py`）。
  **代码路径已用 MinIO 全链路实测通过**（上传 201 + 公开 URL 200 字节一致）；换真实阿里云 OSS 只改 5 个 `S3_*` 值。
  本地复现/验证：`cd backend && docker compose -f docker-compose.minio.yml up -d && cp .env.minio.example .env`（重启后端）。
  两个部署坑见 `backend/.env.minio.example` 顶部注释（boto3 需 pip 装、代理需 NO_PROXY 内网端点）。
- 短信切真实供应商（aliyun）：`.env` 设 `SMS_PROVIDER=aliyun` + 阿里云凭证（`ALIYUN_SMS_*`）。
  **注意**：邮箱验证码目前只写日志、不真发邮件——上线前要么接邮件服务商，要么登录页去掉「邮箱」入口。
- 迁移 0009 是破坏性的（重建 FK + 触发器），生产低峰期执行 `alembic upgrade head`。
- 部署：`backend/Dockerfile` + `backend/docker-compose.prod.yml`。
