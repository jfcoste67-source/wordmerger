#!/usr/bin/env pwsh
<#
.SYNOPSIS
Deploy WordMerger to a remote Ubuntu server.

.DESCRIPTION
- Builds a deployment artifact zip from the current workspace
- Runs remote prechecks to reduce impact risk on co-hosted services
- Uploads artifact and executes deploy/install.sh on the server
- Verifies service status and health endpoint after deployment

.EXAMPLE
./deploy/deploy_wordmerger.ps1 -ServerHost 69.62.105.107 -ServerUser root -SshKeyPath "C:/path/to/ssh.normalized.key"
#>

param(
    [string]$ServerHost = "69.62.105.107",
    [string]$ServerUser = "root",
    [string]$SshKeyPath = "C:/Users/jfcoste/OneDrive/Apps/WebAppPS8/ssh.normalized.key",
    [string]$RemoteBasePath = "/opt/wordmerger",
    [string]$ServiceName = "wordmerger",
    [int]$ServicePort = 8002,
    [switch]$SkipPrecheck,
    [switch]$SkipHealthCheck,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][string]$SshKey,
        [Parameter(Mandatory = $true)][string]$SshTarget
    )

  $normalizedScript = $Script -replace "`r`n", "`n"
  $normalizedScript = $normalizedScript -replace "`r", "`n"
  $normalizedScript | & ssh -i $SshKey $SshTarget "tr -d '\r' | bash -s"
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed with exit code $LASTEXITCODE"
    }
}

Assert-Command -Name "ssh"
Assert-Command -Name "scp"
Assert-Command -Name "tar"

if (-not (Test-Path $SshKeyPath)) {
    throw "SSH key not found: $SshKeyPath"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$sshTarget = "$ServerUser@$ServerHost"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$artifactName = "wordmerger-deploy-$stamp.tar.gz"
$artifactPath = Join-Path $projectRoot $artifactName
$remoteStage = "/tmp/wordmerger-$stamp"
$remoteArtifact = "$remoteStage/$artifactName"

Write-Host "Starting WordMerger deployment to $sshTarget" -ForegroundColor Cyan
Write-Host "Project root: $projectRoot" -ForegroundColor DarkGray

Push-Location $projectRoot
try {
    Write-Host "Building deployment artifact..." -ForegroundColor Cyan
    if (Test-Path $artifactPath) {
      Remove-Item $artifactPath -Force
    }
    & tar -czf $artifactPath app deploy schemas templates requirements.txt
    if ($LASTEXITCODE -ne 0) {
      throw "Artifact creation failed"
    }

    $artifactInfo = Get-Item $artifactPath
    Write-Host "Artifact: $($artifactInfo.FullName) ($([math]::Round($artifactInfo.Length / 1KB, 1)) KB)" -ForegroundColor Green

    if (-not $SkipPrecheck) {
        Write-Host "Running remote prechecks..." -ForegroundColor Cyan

        $forceFlag = if ($Force) { "1" } else { "0" }
        $precheckScript = @'
set -eu
      SERVICE_NAME='__SERVICE_NAME__'
      SERVICE_PORT='__SERVICE_PORT__'
      FORCE_FLAG='__FORCE_FLAG__'

echo "== Remote precheck =="
echo "Host: $(hostname)"

echo
echo "[1] Existing systemd service state"
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\\.service"; then
  systemctl is-enabled "${SERVICE_NAME}" || true
  systemctl is-active "${SERVICE_NAME}" || true
else
  echo "Service ${SERVICE_NAME}.service not present (ok for first deploy)"
fi

echo
echo "[2] Port usage on :${SERVICE_PORT}"
PORT_LINES=$(ss -ltnp "( sport = :${SERVICE_PORT} )" | tail -n +2 || true)
if [ -n "${PORT_LINES}" ]; then
  echo "${PORT_LINES}"
  if ! echo "${PORT_LINES}" | grep -Eiq "(uvicorn|wordmerger|python)"; then
    if [ "${FORCE_FLAG}" != "1" ]; then
      echo "Blocking deploy: port ${SERVICE_PORT} appears used by another app. Re-run with -Force if intended."
      exit 22
    fi
    echo "Force mode enabled: continuing despite possible port conflict"
  fi
else
  echo "Port ${SERVICE_PORT} is free"
fi

echo
echo "[3] Web server presence (informational)"
systemctl is-active nginx 2>/dev/null || true
systemctl is-active apache2 2>/dev/null || true
'@
  $precheckScript = $precheckScript.Replace("__SERVICE_NAME__", $ServiceName)
  $precheckScript = $precheckScript.Replace("__SERVICE_PORT__", $ServicePort.ToString())
  $precheckScript = $precheckScript.Replace("__FORCE_FLAG__", $forceFlag)

        Invoke-RemoteScript -Script $precheckScript -SshKey $SshKeyPath -SshTarget $sshTarget
        Write-Host "Prechecks passed." -ForegroundColor Green
    }

    Write-Host "Creating remote staging directory..." -ForegroundColor Cyan
    & ssh -i $SshKeyPath $sshTarget "mkdir -p $remoteStage"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create remote staging directory"
    }

    Write-Host "Uploading artifact..." -ForegroundColor Cyan
    & scp -i $SshKeyPath $artifactPath "$sshTarget`:$remoteArtifact"
    if ($LASTEXITCODE -ne 0) {
        throw "Artifact upload failed"
    }

    Write-Host "Running remote deploy script..." -ForegroundColor Cyan
    $healthFlag = if ($SkipHealthCheck) { "0" } else { "1" }
    $deployScript = @'
set -eu
  STAMP='__STAMP__'
  STAGE='__REMOTE_STAGE__'
  ARTIFACT='__REMOTE_ARTIFACT__'
  SERVICE_NAME='__SERVICE_NAME__'
  REMOTE_BASE='__REMOTE_BASE__'
  HEALTH_FLAG='__HEALTH_FLAG__'

WORKDIR='${STAGE}/work'
BACKUP="/opt/wordmerger-backup-${STAMP}.tgz"

mkdir -p "${WORKDIR}"
tar -xzf "${ARTIFACT}" -C "${WORKDIR}"
cd "${WORKDIR}"

if [ -d "${REMOTE_BASE}" ]; then
  tar -czf "${BACKUP}" -C /opt wordmerger || true
  echo "Backup created: ${BACKUP}"
fi

chmod +x deploy/install.sh
./deploy/install.sh

systemctl is-active "${SERVICE_NAME}"

if [ "${HEALTH_FLAG}" = "1" ]; then
  HEALTH_OK=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS "http://127.0.0.1:__SERVICE_PORT__/health"; then
      HEALTH_OK=1
      break
    fi
    sleep 1
  done
  if [ "${HEALTH_OK}" != "1" ]; then
    echo "Health check failed after retries"
    exit 7
  fi
fi

echo "Remote deploy complete"
'@
    $deployScript = $deployScript.Replace("__STAMP__", $stamp)
    $deployScript = $deployScript.Replace("__REMOTE_STAGE__", $remoteStage)
    $deployScript = $deployScript.Replace("__REMOTE_ARTIFACT__", $remoteArtifact)
    $deployScript = $deployScript.Replace("__SERVICE_NAME__", $ServiceName)
    $deployScript = $deployScript.Replace("__REMOTE_BASE__", $RemoteBasePath)
    $deployScript = $deployScript.Replace("__HEALTH_FLAG__", $healthFlag)
    $deployScript = $deployScript.Replace("__SERVICE_PORT__", $ServicePort.ToString())

    Invoke-RemoteScript -Script $deployScript -SshKey $SshKeyPath -SshTarget $sshTarget

    Write-Host "Deployment succeeded." -ForegroundColor Green
    Write-Host "Server: $sshTarget" -ForegroundColor Green
    Write-Host "Service: $ServiceName" -ForegroundColor Green
    Write-Host "Health endpoint: http://127.0.0.1:$ServicePort/health" -ForegroundColor Green
}
finally {
    Pop-Location
}
