# ============================================================
# 这个文件是干什么的：验证码发送的统一出入口——console 后端只写日志（开发用），
#   aliyun 后端调阿里云短信 SendSms 接口真发短信。邮件验证码暂只写日志（接邮件服务商是后续项）。
# 它对应产品里的什么功能：登录弹窗的"发送验证码"按钮，用户手机上收到的那条短信。
# 如果它出错了，用户会看到什么现象：收不到验证码，登录不上，所有需要账号的功能都用不了。
# ============================================================
import base64
import hashlib
import hmac
import json
import logging
import secrets
import uuid
from datetime import datetime, timezone
from typing import Dict
from urllib.parse import quote

import httpx

from app.core.config import settings
from app.core.errors import AppError

logger = logging.getLogger("app.sms")

_ALIYUN_ENDPOINT = "https://dysmsapi.aliyuncs.com/"


def send_login_code(identifier_type: str, identifier: str, code: str) -> None:
    """发验证码。手机号走配置的短信服务商；邮箱暂时只写日志（邮件服务商是生产 TODO）。
    服务商调用失败抛 500 INTERNAL——用户侧表现为"发送失败请重试"，不静默吞掉。"""
    if identifier_type == "phone" and settings.sms_provider == "aliyun":
        _send_aliyun_sms(identifier, code)
        return
    # console：开发/联调期验证码进日志（dev 环境另有万能码 888888）
    logger.info("验证码 %s -> %s:%s", code, identifier_type, identifier)


def aliyun_signature(params: Dict[str, str], access_key_secret: str) -> str:
    """阿里云 RPC 签名 V1.0（HMAC-SHA1）。单独成函数便于测试：
    规范化参数 → GET&%2F&<编码后的参数串> → HMAC-SHA1 → base64。"""
    def pe(s: str) -> str:
        # 阿里云规范：空格转 %20（quote 默认行为）、~ 不转义、其余按 RFC3986
        return quote(str(s), safe="~")

    canonical = "&".join(f"{pe(k)}={pe(v)}" for k, v in sorted(params.items()))
    string_to_sign = "GET&%2F&" + pe(canonical)
    digest = hmac.new(
        (access_key_secret + "&").encode(), string_to_sign.encode(), hashlib.sha1
    ).digest()
    return base64.b64encode(digest).decode()


def _send_aliyun_sms(phone: str, code: str) -> None:
    params = {
        "AccessKeyId": settings.aliyun_sms_access_key_id,
        "Action": "SendSms",
        "Format": "JSON",
        "PhoneNumbers": phone,
        "RegionId": "cn-hangzhou",
        "SignName": settings.aliyun_sms_sign_name,
        "SignatureMethod": "HMAC-SHA1",
        "SignatureNonce": uuid.uuid4().hex,
        "SignatureVersion": "1.0",
        "TemplateCode": settings.aliyun_sms_template_code,
        "TemplateParam": json.dumps({"code": code}),
        "Timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "Version": "2017-05-25",
    }
    params["Signature"] = aliyun_signature(params, settings.aliyun_sms_access_key_secret)
    try:
        resp = httpx.get(_ALIYUN_ENDPOINT, params=params, timeout=10)
        body = resp.json()
    except Exception as exc:
        logger.error("阿里云短信调用异常：%s", exc)
        raise AppError(500, "INTERNAL", "验证码发送失败，请稍后重试")
    if body.get("Code") != "OK":
        # 常见：签名错误 / 模板未审核 / 触发阿里云侧频控（isv.BUSINESS_LIMIT_CONTROL）
        logger.error("阿里云短信返回失败：%s", body)
        raise AppError(500, "INTERNAL", "验证码发送失败，请稍后重试")
    logger.info("阿里云短信已发送 -> %s（RequestId=%s）", phone, body.get("RequestId"))


def generate_code() -> str:
    return f"{secrets.randbelow(1000000):06d}"
