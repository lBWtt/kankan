# ============================================================
# 这个文件是干什么的：后端的"设置面板"——集中读取数据库地址、缓存地址、对象存储、
#   短信服务商等配置，其他代码都从这里拿配置，不自己到处写死。
# 它对应产品里的什么功能：不对应单一功能，是后端连接外部世界的总开关。
# 如果它出错了，用户会看到什么现象：后端启动即失败，App 完全无法联网取数据。
# ============================================================
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict

# 开发用 JWT 默认密钥：万能验证码 888888 的启用条件之一就是密钥还是这个默认值——
# 任何真实部署只要换过 JWT_SECRET，万能码立即失效（即便忘配 APP_ENV=prod，也多一道防线）。
DEFAULT_DEV_JWT_SECRET = "dev-secret-change-in-prod"


class Settings(BaseSettings):
    """全局配置：优先读环境变量 / .env 文件，否则用本地开发默认值（与 docker-compose.yml 一致）。
    生产部署清单见 .env.example——上线前必改项都在里面标了【生产必改】。"""

    database_url: str = "postgresql+psycopg2://ccpj:ccpj_dev@localhost:15432/ccpj"
    redis_url: str = "redis://localhost:6379/0"

    # dev / prod：dev 环境登录接受万能验证码 888888（无短信服务商时本地可测；还需密钥为默认值）
    app_env: str = "dev"
    # JWT 签名密钥——上线前必须改成强随机值并放环境变量（prod 下用默认值会拒绝启动）
    jwt_secret: str = DEFAULT_DEV_JWT_SECRET
    jwt_access_ttl_seconds: int = 7200          # access token 2 小时
    jwt_refresh_ttl_seconds: int = 2592000      # refresh token 30 天

    # ---- 媒体存储：local（本地盘，经 /uploads 静态托管）或 s3（S3 兼容对象存储，
    #      阿里云 OSS 的 S3 兼容端点 / AWS S3 / MinIO 都可用）----
    storage_backend: str = "local"
    upload_dir: str = "uploads"                  # local 后端的落盘目录（相对 backend/）
    s3_endpoint_url: str = ""                    # 如 https://oss-cn-hangzhou.aliyuncs.com
    s3_bucket: str = ""
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""
    s3_region: str = ""
    s3_public_base_url: str = ""                 # 文件公开访问域名（CDN/Bucket 域名），如 https://media.example.com

    # ---- 短信服务商：console（验证码只写日志，开发用）或 aliyun（阿里云短信）----
    sms_provider: str = "console"
    aliyun_sms_access_key_id: str = ""
    aliyun_sms_access_key_secret: str = ""
    aliyun_sms_sign_name: str = ""               # 短信签名（如：AI创意发现）
    aliyun_sms_template_code: str = ""           # 模板 CODE（模板须含 ${code} 变量）

    # ---- AI 抓取管线：候选内容整理用的 Claude API（不配 key 也不影响服务运行，
    #      只是 python -m app.pipeline process 跑不了真实整理）----
    anthropic_api_key: str = ""
    # claude-opus-4-8（Opus 4.8）是当前在售模型，无需日期后缀即可调用。
    #（PR#4 曾误改为 claude-opus-4-1-20250805——那是 zai 训练数据过时导致的误判，已还原。）
    anthropic_model: str = "claude-opus-4-8"

    # 分享卡回流的 Web 分享页域名（Web 分享页未建，先占位，上线前改环境变量）
    share_base_url: str = "https://share.example.dev"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()


def validate_production_settings(s: Settings = settings) -> List[str]:
    """生产环境启动前的自检：致命问题直接拒绝启动（抛 RuntimeError），次要问题返回警告列表。
    dev 环境不做任何拦截。"""
    if s.app_env == "dev":
        return []
    errors, warnings = [], []
    if s.jwt_secret == "dev-secret-change-in-prod":
        errors.append("jwt_secret 仍是开发默认值——所有用户令牌可被伪造，必须换强随机值")
    if s.sms_provider == "console":
        errors.append("sms_provider=console——验证码只写日志，线上用户将无法登录")
    if s.sms_provider == "aliyun" and not (
        s.aliyun_sms_access_key_id and s.aliyun_sms_access_key_secret
        and s.aliyun_sms_sign_name and s.aliyun_sms_template_code
    ):
        errors.append("sms_provider=aliyun 但密钥/签名/模板配置不全")
    if s.storage_backend == "s3" and not (
        s.s3_endpoint_url and s.s3_bucket and s3_keys_present(s) and s.s3_public_base_url
    ):
        errors.append("storage_backend=s3 但端点/桶/密钥/公开域名配置不全")
    if s.storage_backend == "local":
        warnings.append("storage_backend=local——媒体落在单机磁盘，扩容或换机会丢，建议尽快切对象存储")
    if s.share_base_url == "https://share.example.dev":
        warnings.append("share_base_url 仍是占位域名，分享卡链接会 404")
    if errors:
        raise RuntimeError("生产配置自检失败：\n- " + "\n- ".join(errors))
    return warnings


def s3_keys_present(s: Settings) -> bool:
    return bool(s.s3_access_key_id and s.s3_secret_access_key)


def dev_login_enabled(s: Settings = settings) -> bool:
    """万能验证码 888888 是否启用：仅当 dev 环境 **且** JWT 仍是默认开发密钥时为真。
    防的是"部署时忘配 APP_ENV=prod"这一致命脚印——只要运维换过 JWT_SECRET，
    哪怕环境标还停在 dev，万能码也已失效，杜绝用 888888 接管任意账号。"""
    return s.app_env == "dev" and s.jwt_secret == DEFAULT_DEV_JWT_SECRET
