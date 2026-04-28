# setup_and_launch.ps1
# 1. 预写 GraphPrinter ini 配置 (RemoteControl + OutputDir)
# 2. 启动 UE + 执行 ue_open_assets.py

$ProjectDir  = "d:\UE\COLMM\GASPALS"
$UE          = "D:\UE\UnrealEngine_Animation_Tech\Engine\Binaries\Win64\UnrealEditor.exe"
$UProject    = "$ProjectDir\GASPALS.uproject"
$Script      = "$ProjectDir\Tools\ue_open_assets.py"
$OutputRoot  = "$ProjectDir\Saved\Screenshots\Blueprints"
$StagingDir  = "$ProjectDir\Saved\Screenshots\_staging"
$Log         = "$ProjectDir\Saved\Logs\batch_final.log"

# 确保目录存在
New-Item -ItemType Directory -Force -Path $OutputRoot  | Out-Null
New-Item -ItemType Directory -Force -Path $StagingDir  | Out-Null

# ── 写 GraphPrinter 配置 ──────────────────────────────────────────────────────
$IniDir  = "$ProjectDir\Saved\Config\WindowsEditor"
New-Item -ItemType Directory -Force -Path $IniDir | Out-Null

$GpIni   = "$IniDir\EditorPerProjectUserSettings.ini"
$staging = $StagingDir.Replace("\", "/")

# 如果 ini 已存在，移除旧的 GraphPrinter 配置段再追加新的
if (Test-Path $GpIni) {
    $content = Get-Content $GpIni -Raw
    $content = $content -replace '(?ms)\[/Script/WidgetPrinter\.WidgetPrinterSettings\].*?(?=\[|$)', ''
    $content = $content -replace '(?ms)\[/Script/GraphPrinterRemoteControl\.GraphPrinterRemoteControlSettings\].*?(?=\[|$)', ''
    Set-Content $GpIni $content
}

# 追加新配置 (用单引号 here-string 避免 [ 被 PowerShell 解析为类型)
$iniBlock = @"

[/Script/WidgetPrinter.WidgetPrinterSettings]
OutputDirectory=(Path="$staging")

[/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings]
bEnableRemoteControl=True
ServerURL=ws://127.0.0.1:3000/
"@
Add-Content $GpIni $iniBlock

Write-Output "[Setup] GraphPrinter ini written: $GpIni"
Write-Output "[Setup] Staging dir: $StagingDir"
Write-Output "[Setup] Output root: $OutputRoot"

# ── 关闭旧的编辑器实例 ────────────────────────────────────────────────────────
Stop-Process -Name UnrealEditor -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Remove-Item $Log -ErrorAction SilentlyContinue
Remove-Item "$ProjectDir\Tools\.ready" -ErrorAction SilentlyContinue

# ── 启动 UE 编辑器 ────────────────────────────────────────────────────────────
Write-Output "[Setup] Launching UE Editor..."
Start-Process -FilePath $UE `
    -ArgumentList "`"$UProject`" -ExecCmds=`"py $Script`" -log -abslog=`"$Log`" -unattended" `
    -WindowStyle Normal

Write-Output "[Setup] Done. Monitor: $Log"
Write-Output "[Setup] Screenshots will appear in: $OutputRoot"
