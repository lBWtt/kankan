# ============================================================
# 这个文件是干什么的：列表"翻页书签"（游标）的编码/解码工具——把排序位置打包成
#   一个不透明字符串发给客户端，客户端原样带回来取下一页。
# 它对应产品里的什么功能：发现页/候选池等所有列表的下拉加载更多。
# 如果它出错了，用户会看到什么现象：列表翻页报错、内容重复或跳条。
# ============================================================
import base64
import binascii
import json
from typing import List

from app.core.errors import AppError


def encode_cursor(parts: List[str]) -> str:
    """把排序键（如 [published_at, id]）编码成不透明游标字符串。"""
    raw = json.dumps(parts, ensure_ascii=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii")


def decode_cursor(cursor: str, expected_len: int) -> List[str]:
    """解码客户端带回的游标；任何畸形输入都报 422，绝不让它进 SQL。"""
    try:
        parts = json.loads(base64.urlsafe_b64decode(cursor.encode("ascii")))
        if not isinstance(parts, list) or len(parts) != expected_len:
            raise ValueError
        return [str(p) for p in parts]
    except (ValueError, binascii.Error, UnicodeDecodeError, json.JSONDecodeError):
        raise AppError(422, "VALIDATION_FAILED", "cursor 无效", {"cursor": cursor})
