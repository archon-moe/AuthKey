$logLocation = "%userprofile%\AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt"
$path = [System.Environment]::ExpandEnvironmentVariables($logLocation)

$baseUrl = "https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog"

if (-Not [System.IO.File]::Exists($path)) {
    Write-Host "Cannot find the log file! Make sure to open the wish history first! Or try to restart your PowerShell as administrator" -ForegroundColor Red
    return
}

$logs = Get-Content -Path $path
$m = $logs -match "(?m).:/.+(GenshinImpact_Data)"
$m[0] -match "(.:/.+(GenshinImpact_Data))" >$null

if ($matches.Length -eq 0) {
    Write-Host "Cannot find the wish history url! Make sure to open the wish history first!" -ForegroundColor Red
    return
}

$gamedir = $matches[1]

$webCachesDir = "$gamedir/webCaches"
$versionPattern = '^\d+\.\d+\.\d+\.\d+$'
$latestPatchDir = Get-ChildItem -Path $webCachesDir -Directory | Where-Object { $_.Name -match $versionPattern } | Sort-Object { $_.Name } -Descending | Select-Object -First 1

$cachefile = "$($latestPatchDir.FullName)\Cache\Cache_Data\data_2"
$tmpfile = "$env:TEMP/ch_data_2"
Write-Output $cachefile
Copy-Item $cachefile -Destination $tmpfile

$content = Get-Content -Encoding UTF8 -Raw $tmpfile

$pattern = 'authkey=(.*?)&game_biz'
$matchedData = Select-String -InputObject $content -Pattern $pattern -AllMatches

$authKeys = @()
foreach ($match in $matchedData.Matches) {
    $authKeys += $match.Groups[1].Value
}
$authKeys = $authKeys | Select-Object -Unique

Write-Host "$($authKeys.Length) unique key(s) found in cache. Checking which are still active..."

function Get-UidFromGachaResponse($response) {
    if ($response.data -and $response.data.list -and $response.data.list.Count -gt 0) {
        return $response.data.list[0].uid
    }
    return $null
}

$activeKeys = @()

foreach ($authKey in $authKeys) {
    $url = $baseUrl + "?authkey=$authKey&win_mode=fullscreen&authkey_ver=1&sign_type=2&auth_appid=webview_gacha&init_type=301&gacha_type=301&page=1&size=20&end_id=0&lang=en"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ContentType 'application/json'
    }
    catch {
        $response = $null
    }

    if ($response -and $response.message -eq "OK") {
        $uid = Get-UidFromGachaResponse $response
        $activeKeys += [PSCustomObject]@{
            AuthKey = $authKey
            Uid     = if ($uid) { $uid } else { "unknown (no wish history on banner 301)" }
            Url     = $url
        }
    }
}

if ($activeKeys.Length -eq 0) {
    Write-Host "No active keys found." -ForegroundColor Red
    return
}

Write-Host "`n$($activeKeys.Length) active key(s) found:`n"
$i = 1
foreach ($k in $activeKeys) {
    Write-Host "[$i] UID: $($k.Uid)"
    Write-Host "    authkey: $($k.AuthKey)"
    Write-Host "    url: $($k.Url)`n"
    $i++
}

if ($activeKeys.Length -eq 1) {
    Set-Clipboard -Value $activeKeys[0].AuthKey
    Write-Host "Authkey copied to clipboard."
}
else {
    $choice = Read-Host "Multiple accounts found. Enter the number of the key to copy to clipboard (or press Enter to skip)"
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $activeKeys.Length) {
        $selected = $activeKeys[[int]$choice - 1]
        Set-Clipboard -Value $selected.AuthKey
        Write-Host "Authkey for UID $($selected.Uid) copied to clipboard."
    }
}
