<#
PictureViewer2 — Windows 构建脚本

用法：
  pwsh -File scripts\build_windows.ps1 [选项]

选项：
  -Mode <release|debug|profile>   构建模式，默认 release
  -Sqlite <download|system>       sqlite3 来源，默认 download（Windows 没有系统 sqlite3.dll）
  -Clean                          构建前执行 flutter clean
  -NoPub                          跳过 flutter pub get
  -FlutterBin <路径>              指定 flutter 可执行文件

产物：build\windows\<架构>\runner\<模式>\pictureviewer.exe
日志：<应用根>\logs\build_windows_<时间戳>.log（可用环境变量 APP_LOG_DIR 覆盖）

环境变量覆盖：FLUTTER_BIN、APP_LOG_DIR、FLUTTER_STORAGE_BASE_URL、PUB_HOSTED_URL

关于 sqlite3 的两条已知坑：
  1. 默认 source 会从 GitHub 下载预编译的 sqlite3.dll；公司网络或国内网络可能超时。
     处置：配置 HTTP(S)_PROXY 后重试，或在 pubspec.yaml 的 hooks 段把 source 写成
     「windows: sqlite3」并自备 sqlite3.dll。
  2. 若 pubspec.yaml 把 source 写成标量 system，Windows 构建会去找系统 sqlite3.dll，
     Windows 上通常不存在，会构建失败。本脚本会检测并提示。

本脚本的工作记录见同目录 build_windows.ps1.projectlog.md。
#>

[CmdletBinding()]
param(
    [ValidateSet('release', 'debug', 'profile')][string]$Mode = 'release',
    [ValidateSet('download', 'system')][string]$Sqlite = 'download',
    [switch]$Clean,
    [switch]$NoPub,
    [string]$FlutterBin = $env:FLUTTER_BIN
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Module = 'build_windows'
$ScriptDir = $PSScriptRoot
$AppRoot = Split-Path -Parent $ScriptDir
$ExeName = 'pictureviewer'

$LogDir = if ([string]::IsNullOrWhiteSpace($env:APP_LOG_DIR)) { Join-Path $AppRoot 'logs' } else { $env:APP_LOG_DIR }
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$script:LogFile = Join-Path $LogDir ("{0}_{1}.log" -f $Module, (Get-Date -Format 'yyyyMMdd_HHmmss'))
Set-Content -LiteralPath $script:LogFile -Value '' -Encoding UTF8

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Message
    )
    $line = '[{0}] [{1,-5}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Module, $Message
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function Write-LogMulti {
    param([string]$Level, [string]$Text)
    foreach ($line in ($Text -split "`r?`n")) {
        Write-Log -Level $Level -Message $line
    }
}

function Test-DllOnPath {
    param([string]$DllName)
    foreach ($dir in ($env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        if (Test-Path -LiteralPath (Join-Path $dir $DllName)) { return $true }
    }
    return $false
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    Write-Log INFO ("应用根目录：{0}" -f $AppRoot)
    Write-Log INFO ("构建模式：{0}；sqlite3 来源：{1}" -f $Mode, $Sqlite)
    Write-Log INFO ("PowerShell：{0}；OS：{1}" -f $PSVersionTable.PSVersion.ToString(), [System.Environment]::OSVersion.VersionString)

    if ($AppRoot.Length -gt 90) {
        Write-Log WARN ("应用根路径长度 {0}，接近 Windows 路径上限，CMake/MSBuild 可能报路径过长" -f $AppRoot.Length)
    }

    if (-not (Test-Path -LiteralPath (Join-Path $AppRoot 'pubspec.yaml'))) {
        throw ("{0} 下没有 pubspec.yaml，这不是 Flutter 项目根目录" -f $AppRoot)
    }

    # ---- 环境变量（未被显式设置时才填镜像；显式设为空串表示关闭）
    if (-not (Test-Path env:FLUTTER_STORAGE_BASE_URL)) { $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn' }
    if (-not (Test-Path env:PUB_HOSTED_URL)) { $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn' }
    Write-Log INFO ("FLUTTER_STORAGE_BASE_URL={0}" -f $(if ([string]::IsNullOrEmpty($env:FLUTTER_STORAGE_BASE_URL)) { '（已关闭）' } else { $env:FLUTTER_STORAGE_BASE_URL }))
    Write-Log INFO ("PUB_HOSTED_URL={0}" -f $(if ([string]::IsNullOrEmpty($env:PUB_HOSTED_URL)) { '（已关闭）' } else { $env:PUB_HOSTED_URL }))

    # ---- 定位 flutter
    $script:Flutter = $null
    if (-not [string]::IsNullOrWhiteSpace($FlutterBin)) {
        if (Test-Path -LiteralPath $FlutterBin) { $script:Flutter = (Resolve-Path -LiteralPath $FlutterBin).Path }
        else { Write-Log WARN ("-FlutterBin 指向的路径不存在：{0}" -f $FlutterBin) }
    }
    if (-not $script:Flutter) {
        $cmd = Get-Command flutter -ErrorAction SilentlyContinue
        if ($cmd) { $script:Flutter = $cmd.Source }
    }
    if (-not $script:Flutter) {
        throw '找不到 flutter。把 flutter\bin 加入 PATH，或用 -FlutterBin <路径> 指定。'
    }
    Write-Log INFO ("flutter：{0}" -f $script:Flutter)

    # ---- sqlite3 配置体检
    $pubspecPath = Join-Path $AppRoot 'pubspec.yaml'
    $pubspecText = Get-Content -LiteralPath $pubspecPath -Raw
    if ($pubspecText -match '(?m)^\s*source:\s*(system|sqlite3mc|sqlcipher)\s*$') {
        Write-Log WARN 'pubspec.yaml 的 hooks 段把 sqlite3 source 写成了标量，Windows 构建会按同一取值处理。'
        Write-Log WARN '建议改成按目标系统区分：source: { windows: sqlite3, linux: system, macos: system }'
    }
    if ($Sqlite -eq 'system') {
        if (Test-DllOnPath 'sqlite3.dll') {
            Write-Log INFO 'PATH 里能找到 sqlite3.dll，按系统库方式构建'
        } else {
            Write-Log WARN 'PATH 里没有 sqlite3.dll。Windows 不带系统 sqlite3，-Sqlite system 很可能构建失败。'
        }
    }

    Push-Location $AppRoot

    function Invoke-Flutter {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
        Write-Log INFO ("执行：flutter {0}" -f ($Arguments -join ' '))
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $code = 0
        try {
            & $script:Flutter @Arguments 2>&1 | Tee-Object -FilePath $script:LogFile -Append | Out-Host
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $saved
        }
        if ($code -ne 0) {
            throw ("flutter {0} 失败，退出码 {1}" -f ($Arguments -join ' '), $code)
        }
    }

    Invoke-Flutter --version

    if ($Clean) { Invoke-Flutter clean }
    if (-not $NoPub) { Invoke-Flutter pub get }

    Invoke-Flutter build windows ("--{0}" -f $Mode)

    # ---- 产物检查
    $outDir = @('x64', 'arm64', 'x86') |
        ForEach-Object { Join-Path $AppRoot ("build\windows\{0}\runner\{1}" -f $_, $Mode) } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $outDir) {
        throw ("构建命令成功，但没找到 build\windows\<架构>\runner\{0} 目录" -f $Mode)
    }
    $exePath = Join-Path $outDir ("{0}.exe" -f $ExeName)
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw ("产物目录里没有 {0}.exe：{1}" -f $ExeName, $outDir)
    }
    $size = [math]::Round((Get-Item -LiteralPath $exePath).Length / 1MB, 2)
    Write-Log INFO ("产物目录：{0}" -f $outDir)
    Write-Log INFO ("可执行文件：{0}（{1} MB）" -f $exePath, $size)

    if (Test-Path -LiteralPath (Join-Path $outDir 'sqlite3.dll')) {
        Write-Log INFO 'sqlite3.dll 已在产物目录内（随包分发，目标机无需另装）'
    } else {
        Write-Log WARN '产物目录里没有 sqlite3.dll。若应用启动即报找不到 sqlite3，请检查 hooks 段的 source 取值。'
    }

    Write-Log INFO '构建成功'
    exit 0
}
catch {
    Write-Log ERROR ("构建失败：{0}" -f $_.Exception.Message)
    Write-LogMulti ERROR $_.Exception.ToString()
    Write-Log ERROR '排查顺序：1) flutter doctor -v 确认 Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载；'
    Write-Log ERROR '          2) 若失败发生在下载 sqlite3 预编译产物，配置代理或改用自备 sqlite3.dll；'
    Write-Log ERROR '          3) 完整输出见上方日志与日志文件。'
    exit 1
}
finally {
    if ((Get-Location).Path -eq $AppRoot) { Pop-Location }
    $stopwatch.Stop()
    Write-Log INFO ("构建结束：耗时 {0:F1}s，日志 {1}" -f $stopwatch.Elapsed.TotalSeconds, $script:LogFile)
}
