#!/bin/bash
# ============================================
#  一键启动前端 App (Git Bash 用)
#  连真后端，走 adb reverse（绕开模拟器坏网卡 + Clash 代理）
#
#  原理：App 连模拟器自己的 127.0.0.1:8000（loopback 一直在，不需要网卡），
#  adb reverse 把它通过 adb 通道转发到本机后端 127.0.0.1:8000。全程本地、不过代理。
#  前提：后端已在 127.0.0.1:8000 跑起来，且模拟器 emulator-5554 已启动。
# ============================================
cd /f/kankan/frontend || exit 1

ADB=/f/android_sdk/platform-tools/adb.exe

echo ""
echo "============================================"
echo " 前端 App 启动中（真后端 / adb reverse 模式）..."
echo " 模拟器: emulator-5554"
echo " 后端:   http://127.0.0.1:8000/api/v1  (经 adb reverse)"
echo "============================================"
echo ""

# 建立端口转发：模拟器内 127.0.0.1:8000 -> 本机 127.0.0.1:8000（每次启动都设，幂等）
"$ADB" reverse tcp:8000 tcp:8000
echo "[adb reverse] tcp:8000 -> host:8000 已建立"
echo ""

flutter run -d emulator-5554 --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
