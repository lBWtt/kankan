# ============================================================
# 这个文件是干什么的：部署准备 + 短信接入的冒烟测试——生产配置自检的拦截行为、
#   存储抽象层（local 后端落盘/出 URL）、阿里云短信签名算法、send-code 全链路回归。
# 它对应产品里的什么功能：上线前的最后一道闸：配置不齐拒绝启动、换存储不丢图、短信能发出去。
# 如果它出错了，用户会看到什么现象：开发者会在上线前发现问题——这正是它存在的目的。
# 用法：先起服务（uvicorn app.main:app），再在 backend/ 下跑：
#   .venv/Scripts/python.exe tests/smoke_v5.py [BASE_URL，默认 http://127.0.0.1:8000]
# ============================================================
import base64
import os
import sys
import time

import httpx
from sqlalchemy import text as sql

from app.core.config import Settings, validate_production_settings
from app.core.db import engine
from app.services.sms import aliyun_signature
from app.services.storage import save_media_file

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

passed, failed = 0, 0


def check(name: str, cond: bool, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def main():
    print("== 1. 生产配置自检（prod 下挡住带病启动）==")
    dev = Settings(app_env="dev")
    check("dev 环境不拦截（默认密钥也放行）", validate_production_settings(dev) == [])

    prod_bad = Settings(app_env="prod")
    try:
        validate_production_settings(prod_bad)
        check("prod + 默认密钥/console 短信 = 拒绝启动", False, "竟然没拦")
    except RuntimeError as e:
        check("prod + 默认密钥/console 短信 = 拒绝启动", "jwt_secret" in str(e) and "sms_provider" in str(e), str(e))

    prod_ok = Settings(
        app_env="prod", jwt_secret="a-strong-random-secret", sms_provider="aliyun",
        aliyun_sms_access_key_id="k", aliyun_sms_access_key_secret="s",
        aliyun_sms_sign_name="签名", aliyun_sms_template_code="SMS_123",
    )
    warnings = validate_production_settings(prod_ok)
    check("prod 配置齐 = 放行且警告本地存储/占位域名",
          any("local" in w for w in warnings) and any("share_base_url" in w for w in warnings), str(warnings))

    prod_s3_bad = Settings(
        app_env="prod", jwt_secret="x", sms_provider="aliyun",
        aliyun_sms_access_key_id="k", aliyun_sms_access_key_secret="s",
        aliyun_sms_sign_name="签名", aliyun_sms_template_code="SMS_123",
        storage_backend="s3", s3_bucket="b",  # 端点/密钥/公开域名缺失
    )
    try:
        validate_production_settings(prod_s3_bad)
        check("s3 配置不全 = 拒绝启动", False, "竟然没拦")
    except RuntimeError as e:
        check("s3 配置不全 = 拒绝启动", "s3" in str(e), str(e))

    print("== 2. 存储抽象层（local 后端）==")
    tmp = os.path.join("uploads", "_smoke_tmp.png")
    os.makedirs("uploads", exist_ok=True)
    with open(tmp, "wb") as f:
        f.write(PNG_1PX)
    url = save_media_file(tmp, "smoke_v5_test.png")
    final = os.path.join("uploads", "smoke_v5_test.png")
    check("save_media_file 返回 /uploads/ URL", url == "/uploads/smoke_v5_test.png", url)
    check("文件已落盘且临时文件已移走", os.path.exists(final) and not os.path.exists(tmp))
    os.remove(final)

    print("== 3. 阿里云短信签名算法 ==")
    params = {
        "AccessKeyId": "testid", "Action": "SendSms", "Format": "JSON",
        "PhoneNumbers": "13800138000", "RegionId": "cn-hangzhou",
        "SignName": "测试签名", "SignatureMethod": "HMAC-SHA1",
        "SignatureNonce": "fixed-nonce", "SignatureVersion": "1.0",
        "TemplateCode": "SMS_001", "TemplateParam": '{"code": "123456"}',
        "Timestamp": "2026-06-11T00:00:00Z", "Version": "2017-05-25",
    }
    sig1 = aliyun_signature(params, "testsecret")
    sig2 = aliyun_signature(params, "testsecret")
    sig3 = aliyun_signature(params, "othersecret")
    check("签名确定性（同参同密钥同结果）", sig1 == sig2 and len(base64.b64decode(sig1)) == 20, sig1)
    check("换密钥签名变化", sig1 != sig3)
    sig4 = aliyun_signature(dict(params, PhoneNumbers="13900139000"), "testsecret")
    check("改参数签名变化（防篡改）", sig1 != sig4)

    print("== 4. send-code 全链路回归（console 后端）==")
    c = httpx.Client(base_url=BASE, timeout=15, trust_env=False)  # trust_env=False 绕过本机代理
    phone = f"129{int(time.time()) % 100000000:08d}"
    r = c.post("/api/v1/auth/send-code", json={"identifier_type": "phone", "identifier": phone})
    check("send-code = 200（console 后端写日志）", r.status_code == 200, r.text)
    r = c.post("/api/v1/auth/login", json={"identifier_type": "phone", "identifier": phone, "code": "888888"})
    check("dev 万能码登录仍可用", r.status_code == 200)
    uid = r.json()["user"]["id"]
    r = c.post("/api/v1/media", headers={"Authorization": f"Bearer {r.json()['access_token']}"},
               files={"file": ("a.png", PNG_1PX, "image/png")})
    check("上传走新存储层 = 201 且 URL 正常", r.status_code == 201 and r.json()["url"].startswith("/uploads/"),
          r.text)
    media_id, media_url = r.json()["id"], r.json()["url"]
    check("上传文件可访问", c.get(media_url).status_code == 200)

    # ---- 清理 ----
    with engine.begin() as conn:
        conn.execute(sql("DELETE FROM project_media WHERE id = CAST(:m AS uuid)"), {"m": media_id})
        conn.execute(sql("DELETE FROM push_preferences WHERE user_id = CAST(:u AS uuid)"), {"u": uid})
        conn.execute(sql("DELETE FROM users WHERE id = CAST(:u AS uuid)"), {"u": uid})
    fpath = os.path.join("uploads", media_url.split("/uploads/")[1])
    if os.path.exists(fpath):
        os.remove(fpath)

    print(f"\n结果：{passed} 通过 / {failed} 失败")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
