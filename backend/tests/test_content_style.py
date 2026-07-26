# ============================================================
# 这个文件是干什么的：**固化**项目文案风格——守住「别再回到 X是一个 模板腔」这条线。
#   纯单元测试 _strip_definition_open（不需要起服务/DB），跑得快。
# 它对应产品里的什么功能：看看/推荐里项目文案的「像不同人写的、别一个模板」质量线
#   （用户反复强调，见 memory project-content-quality-bars）。
# 用法（backend/ 下）：python tests/test_content_style.py
# ============================================================
import sys

from app.services.ai_processor import (
    _strip_definition_open,
    _pick_angle,
    PROJECT_ANGLES,
)

passed = failed = 0


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {extra}")


def main():
    # 1) 定义句开头要被砍掉，剩下的名词短语照读通顺
    cases_strip = [
        ("OpenCut 是一款开源的视频编辑器，可以看作剪映替代", "开源的视频编辑器"),
        ("ComfyUI 是一个基于节点的 AI 绘画工具，用连线搭流程", "基于节点的"),
        ("它是一种把手绘分镜变成短视频的工作流，含转场技巧", "把手绘分镜"),
    ]
    for src, starts in cases_strip:
        out = _strip_definition_open(src)
        check(f"砍定义句开头: {src[:14]}…",
              out.startswith(starts) and "是一" not in out[:6], f"-> {out[:24]}")

    # 2) 非定义句开头不能被误伤
    keep = [
        "每周写周报头疼？把工作流水丢给它自动整理",
        "9 分钟就能搓出一个能跑的 App，全程语音编程",
        "基于 C++ 的轻量级 ONNX 推理库，树莓派也能跑",
    ]
    for s in keep:
        check(f"非定义句不动: {s[:12]}…", _strip_definition_open(s) == s)

    # 3) 砍完太短（<8 字）就别砍，避免砍空
    check("砍完过短则保留", _strip_definition_open("这是一个工具") == "这是一个工具")

    # 4) 空/None 安全
    check("None 安全", _strip_definition_open(None) is None)
    check("空串安全", _strip_definition_open("") == "")

    # 5) 写作角度库存在且随机可取（治「一个模板腔」的另一半）
    check("写作角度库 >=5 种", len(PROJECT_ANGLES) >= 5, str(len(PROJECT_ANGLES)))
    check("能随机取角度", _pick_angle() in PROJECT_ANGLES)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
