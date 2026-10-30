param([switch]$SkipCore)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$buildConfig=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build.json') -Raw | ConvertFrom-Json
if(-not $SkipCore){
    Write-Host '编译传输核心'
    & $buildConfig.cargo ('+'+$buildConfig.toolchain) build --release --locked --manifest-path (Join-Path $taskRoot 'core/Cargo.toml')
    if($LASTEXITCODE -ne 0){throw '传输核心编译失败'}
}
$output=Join-Path $taskRoot 'build\windows\x64\Release'
$staging=Join-Path $taskRoot ('build\windows\x64\publish-'+[Guid]::NewGuid().ToString('N'))
Write-Host '编译 WPF 客户端'
& $buildConfig.dotnet publish (Join-Path $PSScriptRoot 'QuickTransfer.csproj') -c Release -r win-x64 --self-contained true -o $staging --nologo -v minimal
if($LASTEXITCODE -ne 0){throw 'WPF 客户端编译失败'}
Move-Item -LiteralPath (Join-Path $staging 'QuickTransfer.Desktop.exe') -Destination (Join-Path $staging 'QuickTransfer.exe')

# 仅替换当前源码目录内的构建产物，旧产物保留在归档目录。
$workspacePrefix=[IO.Path]::GetFullPath($taskRoot).TrimEnd('\')+'\'
foreach($target in @($output,$staging)){
    if(-not [IO.Path]::GetFullPath($target).StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)){throw '构建目录不在当前工程内'}
}
Get-Process -Name QuickTransfer,QuickTransfer.Desktop -ErrorAction SilentlyContinue | ForEach-Object {
    if($_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq $output){
        $client=$_
        Stop-Process -Id $client.Id -Force
        [void]$client.WaitForExit(10000)
    }
}
if(Test-Path -LiteralPath $output){
    $archive=Join-Path $taskRoot ('build\archive\Windows-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $archive) | Out-Null
    if(-not [IO.Path]::GetFullPath($archive).StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)){throw '归档目录不在当前工程内'}
    Move-Item -LiteralPath $output -Destination $archive
}
Move-Item -LiteralPath $staging -Destination $output
Write-Host ('编译完成：'+(Join-Path $output 'QuickTransfer.exe'))
