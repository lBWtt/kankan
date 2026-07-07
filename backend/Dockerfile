# ============================================================
# 这个文件是干什么的：后端的"装箱说明书"——把代码和依赖打成一个容器镜像，
#   启动时先自动建库/升级表结构（alembic），再起服务。
# 它对应产品里的什么功能：不对应单一功能，是后端能部署到任何服务器的前提。
# 如果它出错了，用户会看到什么现象：新版本发不上线；线上回滚也靠它。
# ============================================================
# 用 3.11 而非 3.9：3.9 已于 2025-10 EOL（不再有安全补丁），
# 且 3.11 性能更好、对 pydantic v2 / SQLAlchemy 2.x / anthropic SDK 支持更稳。
FROM python:3.11-slim

# 国内构建可换源：docker build --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple .
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

WORKDIR /srv/app

# 非 root 运行：即使容器被攻破也限定在 app 用户权限内，符合最小权限原则。
RUN groupadd -r app && useradd -r -g app -d /srv/app -s /usr/sbin/nologin app

COPY requirements.txt .
RUN pip install -i ${PIP_INDEX_URL} -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app

# 上传目录（storage_backend=local 时挂卷持久化；s3 时仅作临时盘）
RUN mkdir -p uploads && chown -R app:app /srv/app

USER app

EXPOSE 8000

# 心跳：依赖标准库，不给镜像加 curl。start-period=60s 给 alembic 升级 + uvicorn 启动留足时间，
#   避免冷启动期被误判为不健康而触发滚动重启循环。
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status==200 else 1)"

# 先升级表结构再起服务；--workers 1 是有意为之：定时任务随 FastAPI 进程跑，
# 多 worker 会重复执行（要扩容先把 services/maintenance.py 拆成独立任务进程）
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1"]
