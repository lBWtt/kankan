@echo off
REM ============================================
REM  一键启动前端 App (双击即可)
REM  连真后端，走 adb reverse（本地 loopback，绕开 Clash 代理）
REM
REM  原理：App 连模拟器自己的 127.0.0.1:8000（loopback 一直在，不需要网卡），
REM  adb reverse 把这个端口通过 adb 通道转发到本机后端 127.0.0.1:8000。
REM  全程本地、不过系统代理，所以 Clash 开着也不影响。
REM
REM  端口说明（重要）：模拟器用 5928/5929 启动，serial = emulator-5928。
REM  因为 Windows 保留了 TCP 端口段 5527-5926（Hyper-V/WSL/Docker 动态占的），
REM  正好盖住模拟器默认端口 5554-5584，默认启动会报 "too many emulator instances"。
REM  查看保留段：netsh int ipv4 show excludedportrange protocol=tcp
REM
REM  前提：后端已在本机 127.0.0.1:8000 跑起来（先双击 start_backend.bat）。
REM        模拟器没起时本脚本会用正确端口自动拉起并等开机完成。
REM ============================================
cd /d F:\kankan\frontend

set ADB=F:\android_sdk\platform-tools\adb.exe
set EMULATOR=F:\android_sdk\emulator\emulator.exe
set AVD=Pixel_3a_API_33_x86_64
set SERIAL=emulator-5928

echo.
echo ============================================
echo  前端 App 启动中（真后端 / adb reverse 模式）...
echo  模拟器: %SERIAL%  (ports 5928,5929)
echo  后端:   http://127.0.0.1:8000/api/v1  (经 adb reverse)
echo ============================================
echo.

REM 若 %SERIAL% 已在线，跳过启动，直接建转发。
"%ADB%" devices | find "%SERIAL%" >nul
if not errorlevel 1 (
  echo [emulator] %SERIAL% 已在线。
  goto reverse
)

echo [emulator] 未检测到 %SERIAL%，正在启动 %AVD% ...
REM 清理残留实例注册，避免 "too many emulator instances"
if exist "%TEMP%\avd\running" rd /s /q "%TEMP%\avd\running" 2>nul
start "" "%EMULATOR%" -avd %AVD% -ports 5928,5929 -no-snapshot -no-boot-anim -no-audio
echo [emulator] 等待设备上线...
"%ADB%" -s %SERIAL% wait-for-device
echo [emulator] 等待开机完成（首次冷启动约 30-60 秒）...

:waitboot
set BOOT=
for /f "usebackq tokens=*" %%b in (`"%ADB%" -s %SERIAL% shell getprop sys.boot_completed 2^>nul`) do set BOOT=%%b
if not "%BOOT%"=="1" (
  timeout /t 2 >nul
  goto waitboot
)
echo [emulator] 开机完成。

:reverse
echo.
REM 建立端口转发：模拟器内 127.0.0.1:8000 -> 本机 127.0.0.1:8000（每次重启都要重建，幂等）
"%ADB%" -s %SERIAL% reverse tcp:8000 tcp:8000
echo [adb reverse] tcp:8000 -^> host:8000 已建立
echo.

flutter run -d %SERIAL% --dart-define=USE_REMOTE=true --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

pause
