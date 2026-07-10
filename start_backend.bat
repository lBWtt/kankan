@echo off
REM ============================================
REM  一键启动后端 (双击即可)
REM  自动绕过系统代理，启动 uvicorn
REM ============================================
cd /d F:\kankan\backend

REM 绕过代理（你的 7890 代理会干扰 Python SSL）
set HTTP_PROXY=
set HTTPS_PROXY=
set no_proxy=*

echo.
echo ============================================
echo  后端启动中...
echo  API 地址: http://127.0.0.1:8000
echo  API 文档: http://127.0.0.1:8000/docs
echo ============================================
echo.

uvicorn app.main:app --port 8000 --host 0.0.0.0 --reload

pause
