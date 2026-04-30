# Preconfigure GraphPrinter and launch the UE editor batch exporter.

$ProjectDir = "d:\UE\COLMM\GASPALS"
$UE = "D:\UE\UnrealEngine_Animation_Tech\Engine\Binaries\Win64\UnrealEditor.exe"
$UProject = "$ProjectDir\GASPALS.uproject"
$Script = "$ProjectDir\Tools\ue_open_assets.py"
$OutputRoot = "$ProjectDir\Saved\Screenshots\Blueprints"
$StagingDir = "$ProjectDir\Saved\Screenshots\_staging"
$Log = "$ProjectDir\Saved\Logs\batch_graphprinter.log"
$WsUrl = "ws://127.0.0.1:3000/"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

$IniDir = "$ProjectDir\Saved\Config\WindowsEditor"
New-Item -ItemType Directory -Force -Path $IniDir | Out-Null

$GpIni = "$IniDir\EditorPerProjectUserSettings.ini"
$StagingConfigPath = $StagingDir.Replace("\", "/")

if (Test-Path $GpIni) {
    $Content = Get-Content $GpIni -Raw
    $Content = $Content -replace '(?ms)\[/Script/WidgetPrinter\.WidgetPrinterSettings\].*?(?=\[|$)', ''
    $Content = $Content -replace '(?ms)\[/Script/GraphPrinterRemoteControl\.GraphPrinterRemoteControlSettings\].*?(?=\[|$)', ''
    Set-Content -Path $GpIni -Value $Content -Encoding UTF8
}

$IniBlock = @"

[/Script/WidgetPrinter.WidgetPrinterSettings]
bIsIncludeWidgetInfoInImageFile=True
Format=PNG
OutputDirectory=(Path="$StagingConfigPath")

[/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings]
bEnableRemoteControl=True
ServerURL="$WsUrl"
"@
Add-Content -Path $GpIni -Value $IniBlock -Encoding UTF8

Write-Output "[Setup] GraphPrinter ini written: $GpIni"
Write-Output "[Setup] Staging dir: $StagingDir"
Write-Output "[Setup] Output root: $OutputRoot"
Write-Output "[Setup] WebSocket URL: $WsUrl"

Stop-Process -Name UnrealEditor -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Remove-Item $Log -ErrorAction SilentlyContinue

Write-Output "[Setup] Launching UE Editor..."
Start-Process -FilePath $UE `
    -ArgumentList "`"$UProject`" -ExecCmds=`"py $Script`" -log -abslog=`"$Log`" -unattended" `
    -WindowStyle Normal

Write-Output "[Setup] Done. Monitor: $Log"
Write-Output "[Setup] Screenshots will appear in: $OutputRoot"
