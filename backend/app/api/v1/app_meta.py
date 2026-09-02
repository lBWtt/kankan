# ============================================================
# 这个文件是干什么的：App 版本管控 / kill-switch。App 启动时调 /app/version-check，
#   后端按「最低支持版本 + 禁用清单」判断：强制升级 / 软提示 / 放行。
# 它对应产品里的什么功能：侧载 APK 的版本控制——发现某版有 bug/漏洞时，运营在后端
#   一个开关就能禁用该版、逼所有人升级，不用发新包。
# 配置在 JSON 文件（默认 /srv/app/app_version.json），改它 docker cp 即生效、不用重启：
#   { "latest_build": 5, "min_supported_build": 1, "blocked_builds": [], "apk_url": "...", ... }
#   - 禁用 build 5：blocked_builds=[5]  或  min_supported_build=6
#   - 发新版 build 6：latest_build=6（低于它的用户看到「有新版」软提示）
# 文件缺失时用下面代码里的默认值（保证接口永不 500）。
# ============================================================
import json
import os

from fastapi import APIRouter, Query

router = APIRouter(prefix="/app", tags=["app"])

_DEFAULT = {
    "latest_build": 5,          # 当前最新构建号（pubspec 的 +N）
    "min_supported_build": 1,   # 低于此值 → 强制升级
    "blocked_builds": [],       # 明确禁用的构建号 → 强制升级
    "apk_url": "https://lovluu.com/downloads/kankan-android.apk",
    "message": "有新版本，建议更新到最新版。",
    "force_message": "当前版本已停用，请更新到最新版后继续使用。",
}
_CONFIG_PATH = os.environ.get("APP_VERSION_CONFIG", "/srv/app/app_version.json")


def _load() -> dict:
    cfg = dict(_DEFAULT)
    try:
        with open(_CONFIG_PATH, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            cfg.update(data)
    except Exception:
        pass  # 文件缺失/损坏 → 用默认，接口不报错
    return cfg


@router.get("/version-check", summary="App 版本检查 / kill-switch（启动时调）")
def version_check(
    build: int = Query(0, description="客户端构建号（pubspec 的 +N）"),
    platform: str = Query("android"),
):
    cfg = _load()
    blocked_list = cfg.get("blocked_builds") or []
    blocked = build in blocked_list
    force = build < int(cfg.get("min_supported_build", 1)) or blocked
    update = build < int(cfg.get("latest_build", 1))
    return {
        "force_update": force,
        "update_available": bool(update and not force),
        "latest_build": cfg.get("latest_build"),
        "apk_url": cfg.get("apk_url"),
        "message": cfg.get("force_message") if force else cfg.get("message"),
    }
