param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (!$OutputDirectory) {
    [xml]$projectFile = Get-Content -LiteralPath (Join-Path $project 'manager/Frostrail.ModManager.csproj')
    $version = $projectFile.Project.PropertyGroup.Version
    $OutputDirectory = Join-Path $project ('build/v' + $version + '/manager')
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
& dotnet build (Join-Path $project 'manager\Frostrail.ModManager.csproj') -c Release -o $output
if ($LASTEXITCODE -ne 0) { throw "Manager build failed: $LASTEXITCODE" }
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination (Join-Path $output 'LICENSE') -Force
Write-Output (Join-Path $output 'FrostrailModManager.exe')
