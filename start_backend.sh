#!/bin/bash
# ============================================
#  一键启动后端 (Git Bash 用)
#  自动绕过系统代理，启动 uvicorn
# ============================================
cd /f/kankan/backend || exit 1

# 绕过代理
export HTTP_PROXY=""
export HTTPS_PROXY=""
export no_proxy="*"

echo ""
echo "============================================"
echo " 后端启动中..."
echo " API 地址: http://127.0.0.1:8000"
echo " API 文档: http://127.0.0.1:8000/docs"
echo "============================================"
echo ""

uvicorn app.main:app --port 8000 --host 0.0.0.0 --reload
