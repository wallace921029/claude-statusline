# ============================================================================
#  Claude Code statusline for Windows 11 / PowerShell 5.1+
#  Save as: %USERPROFILE%\.claude\statusline.ps1
#
#  In %USERPROFILE%\.claude\settings.json :
#  {
#    "statusLine": {
#      "type": "command",
#      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<YOU>\\.claude\\statusline.ps1\""
#    }
#  }
#
#  Errors are appended to %TEMP%\claude\statusline-error.log
# ============================================================================

trap {
    try {
        $errDir = Join-Path $env:TEMP 'claude'
        if (-not (Test-Path $errDir)) { New-Item -ItemType Directory -Path $errDir -Force | Out-Null }
        $msg = "[{0}] {1}`r`n{2}`r`n" -f (Get-Date), $_.Exception.Message, $_.ScriptStackTrace
        Add-Content -Path (Join-Path $errDir 'statusline-error.log') -Value $msg -Encoding UTF8
    } catch {}
    Write-Host "Claude" -NoNewline
    exit 0
}

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

# ── Read JSON from stdin ────────────────────────────────────────────────────
$raw = [Console]::In.ReadToEnd()
if (-not $raw -or -not $raw.Trim()) {
    Write-Host "Claude" -NoNewline
    exit 0
}

try { $json = $raw | ConvertFrom-Json } catch {
    Write-Host "Claude" -NoNewline
    exit 0
}

# ── ANSI color builders ─────────────────────────────────────────────────────
$ESC = [char]27

function RGB { param([int]$R, [int]$G, [int]$B)
    return [string]$ESC + '[38;2;' + $R + ';' + $G + ';' + $B + 'm'
}

$blue    = RGB 0   153 255
$orange  = RGB 255 176 85
$green   = RGB 0   175 80
$cyan    = RGB 86  182 194
$red     = RGB 255 85  85
$yellow  = RGB 230 200 0
$white   = RGB 220 220 220
$magenta = RGB 180 140 255
$dim     = [string]$ESC + '[2m'
$reset   = [string]$ESC + '[0m'
$sep     = ' ' + $dim + [char]0x2502 + $reset + ' '

function Get-PctColor { param([int]$Pct)
    if     ($Pct -ge 90) { return $script:red }
    elseif ($Pct -ge 70) { return $script:yellow }
    elseif ($Pct -ge 50) { return $script:orange }
    else                 { return $script:green }
}

function Build-Bar { param([int]$Pct, [int]$Width)
    if ($Pct -lt 0)   { $Pct = 0 }
    if ($Pct -gt 100) { $Pct = 100 }
    $filled = [int][math]::Floor($Pct * $Width / 100)
    $empty  = $Width - $filled
    $color  = Get-PctColor $Pct
    $f  = if ($filled -gt 0) { ([string][char]0x25CF) * $filled } else { '' }
    $em = if ($empty  -gt 0) { ([string][char]0x25CB) * $empty  } else { '' }
    return $color + $f + $script:dim + $em + $script:reset
}

function Format-EpochTime { param([long]$Epoch, [string]$Style)
    if ($Epoch -le 0) { return '' }
    try { $dt = [System.DateTimeOffset]::FromUnixTimeSeconds($Epoch).LocalDateTime } catch { return '' }
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    switch ($Style) {
        'time'     { return ($dt.ToString('h:mmtt', $ci)).ToLower() }
        'datetime' { return ($dt.ToString('MMM d, h:mmtt', $ci)).ToLower() }
        default    { return ($dt.ToString('MMM d', $ci)).ToLower() }
    }
}

function ConvertTo-EpochSeconds { param($Value)
    if ($null -eq $Value) { return [long]0 }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [long]$Value
    }
    $s = [string]$Value
    if (-not $s -or -not $s.Trim()) { return [long]0 }
    [long]$num = 0
    if ([long]::TryParse($s, [ref]$num)) { return $num }
    try {
        $dto = [System.DateTimeOffset]::Parse(
            $s,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        )
        return [long]$dto.ToUnixTimeSeconds()
    } catch { return [long]0 }
}

function As-Int { param($Value)
    if ($null -eq $Value) { return 0 }
    try { return [int]$Value } catch { return 0 }
}

# ── Pull values out of the JSON payload ─────────────────────────────────────
$modelName = if ($json.model.display_name) { [string]$json.model.display_name } else { 'Claude' }

$size = 200000
if ($json.context_window.context_window_size) {
    $maybeSize = [int]$json.context_window.context_window_size
    if ($maybeSize -gt 0) { $size = $maybeSize }
}

$inputTokens = 0; $cacheCreate = 0; $cacheRead = 0
if ($json.context_window.current_usage) {
    $cu = $json.context_window.current_usage
    $inputTokens = As-Int $cu.input_tokens
    $cacheCreate = As-Int $cu.cache_creation_input_tokens
    $cacheRead   = As-Int $cu.cache_read_input_tokens
}
$current = $inputTokens + $cacheCreate + $cacheRead

$pctUsed = 0
if ($size -gt 0) { $pctUsed = [int][math]::Floor($current * 100 / $size) }

# Effort level from settings
$effort = 'default'
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    try {
        $cfg = Get-Content -Raw -Path $settingsPath -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.effortLevel) { $effort = [string]$cfg.effortLevel }
    } catch {}
}

# Working directory + git
$cwd = $json.cwd
if (-not $cwd) { $cwd = $json.workspace.current_dir }
if (-not $cwd) { $cwd = (Get-Location).Path }
$dirname = if ($cwd) { Split-Path -Leaf $cwd } else { '' }

$gitBranch = ''
$gitDirty  = ''
if ($cwd -and (Test-Path $cwd) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Push-Location $cwd
    try {
        $null = git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0) {
            $br = git symbolic-ref --short HEAD 2>$null
            if ($br) { $gitBranch = ([string]$br).Trim() }
            $st = git --no-optional-locks status --porcelain 2>$null
            if ($st) { $gitDirty = '*' }
        }
    } catch {}
    Pop-Location
}

# Session duration
$sessionDuration = ''
$sessionStart = $json.session.start_time
if ($sessionStart) {
    $startEpoch = ConvertTo-EpochSeconds $sessionStart
    if ($startEpoch -gt 0) {
        $nowEpoch = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $elapsed  = [long]($nowEpoch - $startEpoch)
        if ($elapsed -ge 3600) {
            $h = [int][math]::Floor($elapsed / 3600)
            $m = [int][math]::Floor(($elapsed % 3600) / 60)
            $sessionDuration = "{0}h{1}m" -f $h, $m
        } elseif ($elapsed -ge 60) {
            $sessionDuration = "{0}m" -f ([int][math]::Floor($elapsed / 60))
        } else {
            $sessionDuration = "{0}s" -f $elapsed
        }
    }
}

# ── Build LINE 1 as one big ANSI-encoded string ─────────────────────────────
$pctColor = Get-PctColor $pctUsed
$line1 = $blue + $modelName + $reset + $sep
$line1 += [string][char]0x270D + [string][char]0xFE0F + ' '
$line1 += $pctColor + [string]$pctUsed + '%' + $reset + $sep
$line1 += $cyan + $dirname + $reset
if ($gitBranch) {
    $line1 += ' ' + $green + '(' + $gitBranch
    if ($gitDirty) { $line1 += $red + $gitDirty + $green }
    $line1 += ')' + $reset
}
if ($sessionDuration) {
    $line1 += $sep + $dim + [string][char]0x23F1 + ' ' + $reset + $white + $sessionDuration + $reset
}
$line1 += $sep
switch ($effort) {
    'high'   { $line1 += $magenta + [string][char]0x25CF + ' ' + $effort + $reset }
    'medium' { $line1 += $dim     + [string][char]0x25D1 + ' ' + $effort + $reset }
    'low'    { $line1 += $dim     + [string][char]0x25D4 + ' ' + $effort + $reset }
    default  { $line1 += $dim     + [string][char]0x25D1 + ' ' + $effort + $reset }
}

# ── Rate limits from stdin (preferred) ──────────────────────────────────────
$hasStdinRates      = $false
$fiveHourPct        = $null
$fiveHourResetEpoch = [long]0
$sevenDayPct        = $null
$sevenDayResetEpoch = [long]0

if ($json.rate_limits -and $json.rate_limits.five_hour `
    -and ($null -ne $json.rate_limits.five_hour.used_percentage)) {
    $hasStdinRates = $true
    $fiveHourPct = [int][math]::Round([double]$json.rate_limits.five_hour.used_percentage)
    $fiveHourResetEpoch = ConvertTo-EpochSeconds $json.rate_limits.five_hour.resets_at
    if ($json.rate_limits.seven_day) {
        if ($null -ne $json.rate_limits.seven_day.used_percentage) {
            $sevenDayPct = [int][math]::Round([double]$json.rate_limits.seven_day.used_percentage)
        }
        $sevenDayResetEpoch = ConvertTo-EpochSeconds $json.rate_limits.seven_day.resets_at
    }
}

# ── Fallback: /api/oauth/usage with 60-second file cache ────────────────────
$cacheDir     = Join-Path $env:TEMP 'claude'
$cacheFile    = Join-Path $cacheDir 'statusline-usage-cache.json'
$cacheMaxAge  = 60
$usageData    = $null
$extraEnabled = $false

if (-not (Test-Path $cacheDir)) {
    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch {}
}

if (-not $hasStdinRates) {
    $needsRefresh = $true
    if (Test-Path $cacheFile) {
        try {
            $age = ([DateTime]::Now - (Get-Item $cacheFile).LastWriteTime).TotalSeconds
            if ($age -lt $cacheMaxAge) {
                $needsRefresh = $false
                $usageData = Get-Content -Raw -Path $cacheFile -Encoding UTF8 | ConvertFrom-Json
            }
        } catch {}
    }

    if ($needsRefresh) {
        $token = $env:CLAUDE_CODE_OAUTH_TOKEN
        if (-not $token) {
            $credsFile = Join-Path $env:USERPROFILE '.claude\.credentials.json'
            if (Test-Path $credsFile) {
                try {
                    $creds = Get-Content -Raw -Path $credsFile -Encoding UTF8 | ConvertFrom-Json
                    if ($creds.claudeAiOauth -and $creds.claudeAiOauth.accessToken) {
                        $token = [string]$creds.claudeAiOauth.accessToken
                    }
                } catch {}
            }
        }

        if ($token) {
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = `
                    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
                $headers = @{
                    'Accept'         = 'application/json'
                    'Content-Type'   = 'application/json'
                    'Authorization'  = 'Bearer ' + $token
                    'anthropic-beta' = 'oauth-2025-04-20'
                    'User-Agent'     = 'claude-code/2.1.34'
                }
                $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' `
                    -Headers $headers -Method Get -TimeoutSec 5 -ErrorAction Stop
                if ($resp.five_hour) {
                    $usageData = $resp
                    ($resp | ConvertTo-Json -Depth 10) | Out-File -FilePath $cacheFile -Encoding UTF8
                }
            } catch {}
        }

        if (-not $usageData -and (Test-Path $cacheFile)) {
            try { $usageData = Get-Content -Raw -Path $cacheFile -Encoding UTF8 | ConvertFrom-Json } catch {}
        }
    }

    if ($usageData) {
        if ($usageData.five_hour) {
            $fiveHourPct        = [int][math]::Round([double]$usageData.five_hour.utilization)
            $fiveHourResetEpoch = ConvertTo-EpochSeconds $usageData.five_hour.resets_at
        }
        if ($usageData.seven_day) {
            $sevenDayPct        = [int][math]::Round([double]$usageData.seven_day.utilization)
            $sevenDayResetEpoch = ConvertTo-EpochSeconds $usageData.seven_day.resets_at
        }
        if ($usageData.extra_usage -and $usageData.extra_usage.is_enabled) {
            $extraEnabled = $true
        }
    }
} else {
    if (Test-Path $cacheFile) {
        try {
            $usageData = Get-Content -Raw -Path $cacheFile -Encoding UTF8 | ConvertFrom-Json
            if ($usageData.extra_usage -and $usageData.extra_usage.is_enabled) {
                $extraEnabled = $true
            }
        } catch {}
    }
}

# ── Build rate-limit lines ──────────────────────────────────────────────────
$rateLines = @()
$barWidth  = 10
$resetSym  = [string][char]0x27F3

if ($null -ne $fiveHourPct) {
    $resetTxt = Format-EpochTime $fiveHourResetEpoch 'time'
    $bar      = Build-Bar $fiveHourPct $barWidth
    $clr      = Get-PctColor $fiveHourPct
    $pctTxt   = '{0,3}' -f $fiveHourPct
    $line     = $white + 'current' + $reset + ' ' + $bar + ' ' + $clr + $pctTxt + '%' + $reset
    if ($resetTxt) { $line += ' ' + $dim + $resetSym + $reset + ' ' + $white + $resetTxt + $reset }
    $rateLines += $line
}

if ($null -ne $sevenDayPct) {
    $resetTxt = Format-EpochTime $sevenDayResetEpoch 'datetime'
    $bar      = Build-Bar $sevenDayPct $barWidth
    $clr      = Get-PctColor $sevenDayPct
    $pctTxt   = '{0,3}' -f $sevenDayPct
    $line     = $white + 'weekly' + $reset + '  ' + $bar + ' ' + $clr + $pctTxt + '%' + $reset
    if ($resetTxt) { $line += ' ' + $dim + $resetSym + $reset + ' ' + $white + $resetTxt + $reset }
    $rateLines += $line
}

if ($extraEnabled -and $usageData -and $usageData.extra_usage) {
    $extraPct = [int][math]::Round([double]$usageData.extra_usage.utilization)
    $usedDol  = '{0:0.00}' -f ([double]$usageData.extra_usage.used_credits   / 100.0)
    $limitDol = '{0:0.00}' -f ([double]$usageData.extra_usage.monthly_limit / 100.0)
    $bar      = Build-Bar $extraPct $barWidth
    $clr      = Get-PctColor $extraPct
    $now      = Get-Date
    $nextMo   = $now.AddMonths(1)
    $reset1st = (Get-Date -Year $nextMo.Year -Month $nextMo.Month -Day 1).ToString('MMM d', [System.Globalization.CultureInfo]::InvariantCulture).ToLower()
    $dollar   = [string][char]0x24
    $line = $white + 'extra' + $reset + '   ' + $bar + ' ' + $clr + $dollar + $usedDol + $dim + '/' + $reset + $white + $dollar + $limitDol + $reset + ' ' + $dim + $resetSym + $reset + ' ' + $white + $reset1st + $reset
    $rateLines += $line
}

# ── Output: use Write-Host so Claude Code captures it correctly ────────────
Write-Host $line1 -NoNewline
if ($rateLines.Count -gt 0) {
    Write-Host ''
    Write-Host ''
    for ($i = 0; $i -lt $rateLines.Count; $i++) {
        if ($i -gt 0) { Write-Host '' }
        Write-Host $rateLines[$i] -NoNewline
    }
}

exit 0
