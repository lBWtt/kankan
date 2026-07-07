# ============================================================
# 这个文件是干什么的：Alembic 的"启动器"——执行建表/改表时，从这里拿到
#   数据库地址和全部表定义，然后执行迁移。
# 它对应产品里的什么功能：不对应单一功能，是数据库结构变更的执行入口。
# 如果它出错了，用户会看到什么现象：开发者运行 alembic upgrade head 直接报错，库建不起来。
# ============================================================
from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine

from app.core.config import settings
from app.models import Base  # 导入即注册全部 18 张表

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """离线模式：不连数据库，只生成 SQL 脚本（alembic upgrade head --sql）。"""
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """在线模式：连上数据库直接执行迁移。"""
    connectable = create_engine(settings.database_url)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
