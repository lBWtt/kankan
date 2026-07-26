# Android build/run helper for this Windows workspace.
#
# Why this exists:
# The Windows user profile path contains non-ASCII characters. Gradle/CMake and
# the Kotlin daemon can become slow or flaky when their caches/run directories
# fall back to C:\Users\...\AppData. Keep every transient build path on F:.

param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs = @("run")
)

$ErrorActionPreference = "Stop"

$env:PUB_CACHE = "F:\pub_cache"
$env:GRADLE_USER_HOME = "F:\gradle_home"
$env:TEMP = "F:\temp"
$env:TMP = "F:\temp"
$env:LOCALAPPDATA = "F:\localappdata"
$env:JAVA_HOME = "F:\android_studio\install\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

New-Item -ItemType Directory -Force `
  $env:PUB_CACHE, `
  $env:GRADLE_USER_HOME, `
  $env:TEMP, `
  $env:LOCALAPPDATA | Out-Null

flutter @FlutterArgs
