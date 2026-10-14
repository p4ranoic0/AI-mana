$ErrorActionPreference = 'Stop'
function Assert-Install([string]$name, [bool]$ok) {
  Write-Host "CHECK $name : $ok"
  if (-not $ok) { throw "$name failed" }
}
$root = Join-Path $env:RUNNER_TEMP "aimana-installer-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$env:USERPROFILE = Join-Path $root 'profile'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData/Local'
$env:AIMANA_TASK_NAME = "AImanaInstallerCI-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$install = Join-Path $root 'installed'
$sync = Join-Path $root 'synced'
$output = Join-Path $sync 'AImana/usage-relay.json'
$claude = Join-Path $env:USERPROFILE '.claude'
$codex = Join-Path $env:USERPROFILE '.codex/sessions/2026/10/12'
New-Item -ItemType Directory -Force $claude, $codex, $sync | Out-Null
Copy-Item AImana/Relay/Tests/Fixtures/codex-session.jsonl (Join-Path $codex 'session.jsonl')
$originalSettings = '{"theme":"dark"}'
[IO.File]::WriteAllText((Join-Path $claude 'settings.json'), $originalSettings)
$installer = (Get-ChildItem dist/AImana-*-Setup.exe | Select-Object -First 1).FullName
$log = Join-Path $root 'install.log'
$args = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$log", "/DIR=$install", "/OUTPUTDIR=$sync", "/TASKNAME=$env:AIMANA_TASK_NAME")
$process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
Write-Host "Installer exit code: $($process.ExitCode)"
if ($process.ExitCode -ne 0 -and (Test-Path $log)) { Get-Content $log | Select-Object -Last 60 | Write-Host }
Assert-Install 'silent install exit' ($process.ExitCode -eq 0)
try {
  $relay = Join-Path $install 'usage-relay.exe'
  Assert-Install 'relay executable' (Test-Path $relay)
  Assert-Install 'task executable' (Test-Path (Join-Path $install 'usage-relay-task.exe'))
  Assert-Install 'runtime DLLs' (@(Get-ChildItem $install -Filter '*.dll').Count -gt 0)
  Assert-Install 'published file' (Test-Path $output)
  schtasks /Query /TN $env:AIMANA_TASK_NAME | Out-Null
  Assert-Install 'scheduled task' ($LASTEXITCODE -eq 0)
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  Assert-Install 'user PATH entry' (($userPath -split ';') -contains $install)
  $sample = Get-Content AImana/Relay/Tests/Fixtures/statusline.json -Raw
  $sample | & $relay statusline-capture | Out-Null
  $doctor = & $relay doctor
  Assert-Install 'doctor' ($LASTEXITCODE -eq 0 -and ($doctor -join "`n") -match 'recent')
} finally {
  $uninstaller = Join-Path $install 'unins000.exe'
  if (Test-Path $uninstaller) {
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    Assert-Install 'silent uninstall exit' ($uninstall.ExitCode -eq 0)
  }
}
schtasks /Query /TN $env:AIMANA_TASK_NAME 2>$null | Out-Null
Assert-Install 'scheduled task removed' ($LASTEXITCODE -ne 0)
Assert-Install 'Claude settings restored' ([IO.File]::ReadAllText((Join-Path $claude 'settings.json')) -eq $originalSettings)
Assert-Install 'user data retained' (Test-Path $output)
Assert-Install 'PATH entry removed' (-not (([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') -contains $install))

# The last check queries a task that must be gone, so its exit code is expected to be non-zero.
exit 0
