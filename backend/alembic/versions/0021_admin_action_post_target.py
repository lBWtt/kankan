"""admin_actions.target_type 白名单加入 'post' 和 'feedback'

背景：后台统一管理马甲/清理违规内容时软删动态（delete_post）会写审计日志
target_type='post'，但 0009 建的 CHECK 白名单只含 project/candidate/report/user，
导致合法审计写入被 CheckViolation 500 掉。'feedback'（handle_feedback 早已在用）
同样不在白名单里，一并补上。

revision: 0021_admin_action_post_target
"""
from alembic import op

revision = "0021_admin_action_post_target"
down_revision = "0020_user_handle"
branch_labels = None
depends_on = None

_OLD = "target_type IN ('project','candidate','report','user')"
_NEW = "target_type IN ('project','candidate','report','user','post','feedback')"


def upgrade() -> None:
    op.drop_constraint("admin_target_type_allowed", "admin_actions", type_="check")
    op.create_check_constraint("admin_target_type_allowed", "admin_actions", _NEW)


def downgrade() -> None:
    op.drop_constraint("admin_target_type_allowed", "admin_actions", type_="check")
    op.create_check_constraint("admin_target_type_allowed", "admin_actions", _OLD)
