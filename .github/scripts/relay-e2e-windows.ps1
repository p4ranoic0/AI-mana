$ErrorActionPreference = 'Stop'
function Assert-Relay([string]$check, [bool]$passed, [object]$actual, [object]$expected) {
  Write-Host "CHECK $check | expected: $expected | actual: $actual"
  if (-not $passed) { throw "$check failed; expected: $expected; actual: $actual" }
}
$bin = (swift build -c release --package-path AImana/Relay --show-bin-path).Trim()
Assert-Relay 'release binary directory' ($LASTEXITCODE -eq 0) $bin 'swift build --show-bin-path succeeds'
$relay = Join-Path $bin 'usage-relay.exe'
$taskExe = Join-Path $bin 'usage-relay-task.exe'
Assert-Relay 'task executable present' (Test-Path $taskExe) $taskExe 'existing file'
$taskCheck = Start-Process -FilePath $taskExe -ArgumentList '--self-check' -Wait -PassThru
Assert-Relay 'task executable self-check' ($taskCheck.ExitCode -eq 0) $taskCheck.ExitCode 0

$root = Join-Path $env:RUNNER_TEMP "relay-e2e-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$env:USERPROFILE = Join-Path $root 'profile'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData/Local'
$env:AIMANA_TASK_NAME = "AImanaUsageRelayCI-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$claude = Join-Path $env:USERPROFILE '.claude'
$codex = Join-Path $env:USERPROFILE '.codex'
$settings = Join-Path $claude 'settings.json'
$output = Join-Path $root 'out/usage-relay.json'
$capture = Join-Path $env:LOCALAPPDATA 'AImana/claude-statusline.json'
New-Item -ItemType Directory -Force (Join-Path $claude 'projects'), (Join-Path $codex 'sessions/2026/10/12') | Out-Null
Copy-Item AImana/Relay/Tests/Fixtures/codex-session.jsonl (Join-Path $codex 'sessions/2026/10/12/session.jsonl')
$originalSettings = '{"theme":"dark"}'
[IO.File]::WriteAllText($settings, $originalSettings)

try {
  $setupOutput = & $relay setup --output $output --interval 1
  $setupExit = $LASTEXITCODE
  Assert-Relay 'setup' ($setupExit -eq 0) "$setupExit`: $($setupOutput -join '; ')" 'exit 0'
  Assert-Relay 'initial output' (Test-Path $output) $output 'existing file'
  $checked = & $relay check $output
  $checkExit = $LASTEXITCODE
  Assert-Relay 'initial output decodes' ($checkExit -eq 0) "$checkExit`: $($checked -join '; ')" 'exit 0'
  $taskQuery = schtasks /Query /TN $env:AIMANA_TASK_NAME
  $taskQueryExit = $LASTEXITCODE
  Assert-Relay 'scheduled task exists' ($taskQueryExit -eq 0) "$taskQueryExit`: $($taskQuery -join '; ')" 'exit 0'
  $configured = (Get-Content $settings -Raw | ConvertFrom-Json).statusLine.command
  if ($configured -match '^"(.+usage-relay\.exe)" statusline-capture$') { $captureExe = $Matches[1] }
  else { $captureExe = '' }
  Assert-Relay 'direct statusline command' ($captureExe.Length -gt 0) $configured '"<usage-relay.exe>" statusline-capture'
  Assert-Relay 'statusline executable present' (Test-Path $captureExe) $captureExe 'existing file'
  $sample = Get-Content AImana/Relay/Tests/Fixtures/statusline.json -Raw
  $psi = [Diagnostics.ProcessStartInfo]::new('cmd.exe')
  $psi.Arguments = '/d /s /c "' + $configured + '"'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $process = [Diagnostics.Process]::Start($psi)
  $process.StandardInput.Write($sample)
  $process.StandardInput.Close()
  $statusOutput = $process.StandardOutput.ReadToEnd()
  $statusError = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  Assert-Relay 'configured statusline exit' ($process.ExitCode -eq 0) "$($process.ExitCode): $statusError" 'exit 0'
  Assert-Relay 'configured statusline text' ($statusOutput.Trim() -eq 'CI Opus') ($statusOutput.Trim()) 'CI Opus'
  Assert-Relay 'statusline capture file' (Test-Path $capture) $capture 'existing file'
  $captured = Get-Content $capture -Raw | ConvertFrom-Json
  Assert-Relay 'statusline capture timestamp' ([bool]$captured.capturedAt) $captured.capturedAt 'nonzero timestamp'
  & $relay run --output $output --no-costs
  $publishExit = $LASTEXITCODE
  Assert-Relay 'publish after capture' ($publishExit -eq 0) $publishExit 0
  $capturedCheck = & $relay check $output
  $captureCheckExit = $LASTEXITCODE
  $captureSummary = $capturedCheck -join '; '
  Assert-Relay 'published captured Claude usage' ($captureCheckExit -eq 0 -and $captureSummary -match 'claude: source=statusline error=- session=23') $captureSummary 'Claude session=23%'
  Assert-Relay 'published fixture Codex usage' ($captureSummary -match 'codex: source=logs error=- session=15') $captureSummary 'Codex session=15%'
  $doctorOutput = & $relay doctor
  $doctorExit = $LASTEXITCODE
  Assert-Relay 'doctor after capture' ($doctorExit -eq 0 -and ($doctorOutput -join "`n") -match '\(recent\)') "$doctorExit`: $($doctorOutput -join '; ')" 'exit 0 and recent capture'
  $before = (Get-Item $output).LastWriteTimeUtc
  Start-Sleep -Seconds 2
  $taskRun = schtasks /Run /TN $env:AIMANA_TASK_NAME
  $taskRunExit = $LASTEXITCODE
  Assert-Relay 'run scheduled task' ($taskRunExit -eq 0) "$taskRunExit`: $($taskRun -join '; ')" 'exit 0'
  $changed = $false
  for ($second = 0; $second -lt 60; $second++) {
    Start-Sleep -Seconds 1
    if ((Get-Item $output).LastWriteTimeUtc -gt $before) { $changed = $true; break }
  }
  $after = (Get-Item $output).LastWriteTimeUtc
  Assert-Relay 'scheduled output modification' $changed $after "later than $before within 60 seconds"
  $scheduledCheck = & $relay check $output
  $scheduledCheckExit = $LASTEXITCODE
  $scheduledSummary = $scheduledCheck -join '; '
  Assert-Relay 'scheduled output decodes' ($scheduledCheckExit -eq 0) "$scheduledCheckExit`: $scheduledSummary" 'exit 0'
  Assert-Relay 'scheduled Claude usage' ($scheduledSummary -match 'claude: source=statusline error=- session=23') $scheduledSummary 'Claude session=23%'
  Assert-Relay 'scheduled Codex usage' ($scheduledSummary -match 'codex: source=logs error=- session=15') $scheduledSummary 'Codex session=15%'
  $doctorOutput = & $relay doctor
  $doctorExit = $LASTEXITCODE
  Assert-Relay 'doctor after scheduled publish' ($doctorExit -eq 0 -and ($doctorOutput -join "`n") -match '\(recent\)') "$doctorExit`: $($doctorOutput -join '; ')" 'exit 0 and recent capture'
} finally {
  $uninstallOutput = & $relay uninstall
  $uninstallExit = $LASTEXITCODE
  Assert-Relay 'uninstall' ($uninstallExit -eq 0) "$uninstallExit`: $($uninstallOutput -join '; ')" 'exit 0'
}
schtasks /Query /TN $env:AIMANA_TASK_NAME 2>$null | Out-Null
$removedTaskExit = $LASTEXITCODE
Assert-Relay 'scheduled task removed' ($removedTaskExit -ne 0) $removedTaskExit 'nonzero query exit'
$restoredSettings = [IO.File]::ReadAllText($settings)
Assert-Relay 'settings restored' ($restoredSettings -eq $originalSettings) $restoredSettings $originalSettings
exit 0
