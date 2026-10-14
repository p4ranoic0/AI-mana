param(
  [ValidateSet('setup','setup-again','doctor','uninstall')][string]$Mode,
  [string]$OutputDir,
  [string]$ResultFile,
  [string]$TaskName,
  [string]$Language = 'en'
)
$ErrorActionPreference = 'Stop'
$relay = Join-Path $PSScriptRoot 'usage-relay.exe'

function Update-UserPath([bool]$Add) {
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @($current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $PSScriptRoot.TrimEnd('\') })
  if ($Add) { $parts += $PSScriptRoot }
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

switch ($Mode) {
  'doctor' { & $relay doctor; break }
  'uninstall' {
    & $relay uninstall
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Update-UserPath $false
    break
  }
  default {
    if ($Mode -eq 'setup-again') {
      $suggested = if (Test-Path (Join-Path $env:USERPROFILE 'iCloudDrive')) { Join-Path $env:USERPROFILE 'iCloudDrive' }
        elseif ($env:OneDrive) { $env:OneDrive } else { $env:USERPROFILE }
      $entered = Read-Host "Folder synced with your phone [$suggested]"
      $OutputDir = if ($entered) { $entered } else { $suggested }
    }
    if (-not $OutputDir) { throw 'Missing output folder' }
    if ($TaskName) { $env:AIMANA_TASK_NAME = $TaskName }
    $output = Join-Path (Join-Path $OutputDir 'AImana') 'usage-relay.json'
    $lines = & $relay setup --output $output 2>&1
    $code = $LASTEXITCODE
    $body = @($lines | ForEach-Object { "$_" })
    if ($code -eq 0) {
      Update-UserPath $true
      $body += ""
      if (($body -join "`n") -match 'Claude Code: not found' -and ($body -join "`n") -match 'Codex: not found') {
        if ($Language -eq 'es') {
          $body += 'No se encontraron datos de Claude Code ni de Codex. Usa AI·mana — set up again desde Inicio después de usar alguna de estas herramientas.'
        } else {
          $body += 'Neither Claude Code nor Codex data was found. Use AI·mana — set up again from the Start menu after using either tool.'
        }
      }
      if ($Language -eq 'es') {
        $body += 'En tu teléfono: AI·mana > Ajustes > Tu computadora > Elegir archivo del relay...'
        $body += "Elige usage-relay.json en $OutputDir\AImana"
      } else {
        $body += 'On your phone: open AI·mana > Settings > Your computer > Choose relay file...'
        $body += "Pick usage-relay.json in $OutputDir\AImana"
      }
    }
    if ($ResultFile) { [IO.File]::WriteAllLines($ResultFile, [string[]]$body, [Text.Encoding]::UTF8) }
    else { $body | Write-Host }
    exit $code
  }
}
