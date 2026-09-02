# ============================================================
# 这个文件是干什么的：定义"用户表"——每个注册用户的账号、昵称、语言、
#   兴趣领域、身份角色，以及将来做会员功能预留的字段。
# 它对应产品里的什么功能：登录注册、"我的"页、onboarding 兴趣采集、发现页个性化推荐。
# 如果它出错了，用户会看到什么现象：登录不上、个人资料丢失、发现页推荐和自己的行业无关。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import ARRAY, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk
from app.models.enums import CONTENT_TYPE, DOMAIN, USER_ROLE, language_enum, quoted_list


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = uuid_pk()
    email: Mapped[Optional[str]] = mapped_column(String(255), unique=True)
    phone: Mapped[Optional[str]] = mapped_column(String(20), unique=True)
    # 稳定用户名（@handle）：注册即发、唯一、可在编辑资料改；搜索/@ 用它。
    # 存小写规范形态（a-z0-9_，字母开头）；nullable 仅为兼容存量行落库顺序，实际全量回填。
    handle: Mapped[Optional[str]] = mapped_column(String(30), unique=True)
    nickname: Mapped[Optional[str]] = mapped_column(String(50))
    avatar_url: Mapped[Optional[str]] = mapped_column(Text)
    bio: Mapped[Optional[str]] = mapped_column(String(500))
    school: Mapped[Optional[str]] = mapped_column(String(100))
    age: Mapped[Optional[int]] = mapped_column(Integer)
    language_preference: Mapped[str] = mapped_column(language_enum, nullable=False, server_default="zh-CN")
    country_region: Mapped[Optional[str]] = mapped_column(String(50))
    # v1.3 新增：兴趣领域（domain 枚举值数组），onboarding 写入，驱动发现页个性化
    interests: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    # 内容类型兴趣（前端「看看」兴趣设置用；与 interests 职业维度正交，互不替代）
    interest_content_types: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    # v1.3 新增：creator / developer / general，可空
    role: Mapped[Optional[str]] = mapped_column(String(20))
    # 管理后台权限标记（文档未明确，补全决策：后台接口需要区分管理员）
    is_admin: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    # 会员能力预留（仅占位，V1 不启用）
    membership_tier: Mapped[Optional[str]] = mapped_column(String(20))
    membership_expires_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))
    # 软删：删号保留记录
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        CheckConstraint(f"role IS NULL OR role IN ({quoted_list(USER_ROLE)})", name="role_allowed"),
        CheckConstraint(f"interests <@ ARRAY[{quoted_list(DOMAIN)}]::text[]", name="interests_allowed"),
        CheckConstraint(
            f"interest_content_types <@ ARRAY[{quoted_list(CONTENT_TYPE)}]::text[]",
            name="interest_content_types_allowed",
        ),
        # C-MDL-2：email/phone 至少有一个，杜绝幽灵账号（两者都可空但不可同时为空）
        CheckConstraint("email IS NOT NULL OR phone IS NOT NULL", name="contact_present"),
        CheckConstraint("age IS NULL OR age BETWEEN 1 AND 120", name="age_valid"),
        # H-MDL-8：软删列的部分索引——只索引未软删的活跃用户，提升登录/查询性能
        Index("ix_users_live", "id", postgresql_where=text("deleted_at IS NULL")),
    )
