# ============================================================
# 把某个真实账号设为管理员（生产用）。生产 dev 万能码已失效，管理员只能这样设。
# 用法：先用你的真手机号在 App/网页登录一次（自动建号），再跑：
#   python make_admin.py 13800001234          # 手机号
#   python make_admin.py you@example.com       # 邮箱
#   python make_admin.py 13800001234 --off     # 取消管理员
# ============================================================
import sys

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import User


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("用法：python make_admin.py <手机号或邮箱> [--off]")
        sys.exit(1)
    ident = args[0]
    on = "--off" not in sys.argv
    db = SessionLocal()
    try:
        field = User.email if "@" in ident else User.phone
        user = db.scalar(select(User).where(field == ident, User.deleted_at.is_(None)))
        if user is None:
            print(f"没找到账号 {ident}——请先用它登录一次（自动建号）再跑本脚本。")
            sys.exit(1)
        user.is_admin = on
        db.commit()
        print(f"{ident}（{user.nickname}）is_admin = {on}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
