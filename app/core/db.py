# ============================================================
# 这个文件是干什么的：后端和数据库之间的"电话总机"——建立数据库连接，
#   并提供每次请求借用/归还连接的标准方式。
# 它对应产品里的什么功能：所有需要存取数据的功能（浏览、收藏、发布……）都经过它。
# 如果它出错了，用户会看到什么现象：所有页面加载转圈后报错，任何操作都保存不上。
# ============================================================
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

# pool_pre_ping：每次借连接前先"喂一声"确认还活着，避免数据库重启后接口报废连接错误
engine = create_engine(settings.database_url, pool_pre_ping=True)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db():
    """FastAPI 依赖：每个请求一个数据库会话，用完自动归还。"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
