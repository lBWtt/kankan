# ============================================================
# 这个文件是干什么的：用户 @handle（稳定用户名）的生成 / 规范化 / 校验。
# 它对应产品里的什么功能：注册时给每个账号发一个 @handle；用户可在编辑资料改；搜索/@ 用它。
# 为什么需要：昵称(nickname)会变，改名后就搜不到人；handle 注册即定、唯一、基本不变，
#   是作者身份的锚（定位：数字游民自我推销，需要一个可分享的稳定标识）。
# 规则：小写 a-z0-9_，长度 3-30，必须字母开头。展示为「@handle」。
# ============================================================
import re
import uuid

# 字母开头，其后可跟字母/数字/下划线；整体 3-30 字符。
_HANDLE_RE = re.compile(r"^[a-z][a-z0-9_]{2,29}$")


def normalize_handle(raw: str) -> str:
    """把用户输入规范化为存库形态：去首尾空白、去可选的前导 @、转小写。"""
    return (raw or "").strip().lstrip("@").strip().lower()


def is_valid_handle(handle: str) -> bool:
    return bool(_HANDLE_RE.match(handle))


def generate_handle(user_id: uuid.UUID) -> str:
    """给新账号发一个默认 handle：u + 用户 UUID 前 8 位十六进制（字母开头、唯一性极高）。
    用户之后可在编辑资料里改成好记的。"""
    return "u" + user_id.hex[:8]
