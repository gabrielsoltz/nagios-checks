#################################################################################
# NAME: 	check_windows_updates.ps1
# TESTED: powershell 2 & 4
#
# I forked this script at version 1.42 from:
# ORIGINAL SCRIPT: https://exchange.nagios.org/directory/Plugins/Operating-Systems/Windows-NRPE/Check-Windows-Updates-using-Powershell/details
# ORIGINAL AUTHOR: Christian Kaufmann, ck@tupel7.de
#
# COMMENT:  Script to check for windows updates with Nagios + NRPE/NSClient++
#
#           Checks:
#           - how many critical and optional updates are available 
#           - whether the system is waiting for reboot after installed updates 
#
#           Features:
#           - properly handles NRPE's 1024b limitation in return packet
#           - configurable return states for pending reboot and optional updates
#           - performance data in return packet shows titles of available critical updates
#           - caches updates in file to reduce network traffic, also dramatically increases script execution speed
#
#			Return Values for NRPE:
#			No updates available - OK (0)
#			Only Hidden Updates - OK (0)
#			Updates already installed, reboot required - WARNING (1)
#			Optional updates available - WARNING (1)
#			Critial updates available - CRITICAL (2)
#			Script errors - UNKNOWN (3)
#
#			NRPE Handler to use with NSClient++:
#			[NRPE Handlers]
#			check_updates=cmd /c echo scripts\check_windows_updates.ps1 $ARG1$ $ARG2$; exit $LastExitCode | powershell.exe -command - 
#
#
# CHANGELOG:
# 1.43 2015-11-29 - Corregí 2 bugs:  $critialTitles = ""; -->  $criticalTitles = ""; /  $criticalTitles += $update.Title + " " -->  $criticalTitles += $update.Title + " `n"
# 1.42 2015-07-20 - strip unwanted characters from returnString
# 1.41 2015-04-24 - removed wuauclt /detectnow if updates available
# 1.4  2015-01-14 - configurable return state for pending reboot
# 1.3  2013-01-04 - configurable return state for optional updates
# 1.2  2011-08-11 - cache updates, periodically update cache file
# 1.1  2011-05-11 - hidden updates only -> state OK
#				 - call wuauctl.exe to show available updates to user
# 1.0  2011-05-10 - initial version
#
#################################################################################

$htReplace = New-Object hashtable
foreach ($letter in (Write-Output ä ae ö oe ü ue Ä Ae Ö Oe Ü Ue ß ss)) {
    $foreach.MoveNext() | Out-Null
    $htReplace.$letter = $foreach.Current
}
$pattern = "[$(-join $htReplace.Keys)]"

$returnStateOK = 0
$returnStateWarning = 1
$returnStateCritical = 2
$returnStateUnknown = 3
$returnStatePendingReboot = $returnStateWarning
$returnStateOptionalUpdates = $returnStateWarning

$updateCacheFile = "check_windows_updates-cache.xml"
$updateCacheExpireHours = "24"

$logFile = "check_windows_update.log"

function LogLine(	[String]$logFile = $(Throw 'LogLine:$logFile unspecified'), 
					[String]$row = $(Throw 'LogLine:$row unspecified')) {
	$logDateTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	Add-Content -Encoding UTF8 $logFile ($logDateTime + " - " + $row) 
}

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"){ 
	Write-Host "updates installed, reboot required"
	if (Test-Path $logFile) {
		Remove-Item $logFile | Out-Null
	}
	if (Test-Path $updateCacheFile) {
		Remove-Item $updateCacheFile | Out-Null
	}
	exit $returnStatePendingReboot
}

if (-not (Test-Path $updateCacheFile)) {
	LogLine -logFile $logFile -row ("$updateCacheFile not found, creating....")
	$updateSession = new-object -com "Microsoft.Update.Session"
	$updates=$updateSession.CreateupdateSearcher().Search(("IsInstalled=0 and Type='Software'")).Updates
	Export-Clixml -InputObject $updates -Encoding UTF8 -Path $updateCacheFile
}

if ((Get-Date) -gt ((Get-Item $updateCacheFile).LastWriteTime.AddHours($updateCacheExpireHours))) {
	LogLine -logFile $logFile -row ("update cache expired, updating....")
	$updateSession = new-object -com "Microsoft.Update.Session"
	$updates=$updateSession.CreateupdateSearcher().Search(("IsInstalled=0 and Type='Software'")).Updates
	Export-Clixml -InputObject $updates -Encoding UTF8 -Path $updateCacheFile
} else {
	LogLine -logFile $logFile -row ("using valid cache file....")
	$updates = Import-Clixml $updateCacheFile
}

if ($updates.Count -eq 0) {
	Write-Host "OK - no pending updates."
	exit $returnStateOK
}

$criticalTitles = "";
$countCritical = 0;
$countOptional = 0;
$countHidden = 0;

foreach ($update in $updates) {
	if ($update.IsHidden) {
		$countHidden++
	}
	elseif ($update.AutoSelectOnWebSites) {
		$criticalTitles += $update.Title + " `n"
		$countCritical++
	} else {
		$countOptional++
	}
}

if (($countCritical + $countOptional) -gt 0) {
	$returnString = "Updates: $countCritical critical, $countOptional optional" + [Environment]::NewLine + "$criticalTitles"
	$returnString = [regex]::Replace($returnString, $pattern, { $htReplace[$args[0].value] })
	if ($returnString.length -gt 1024) {
        Write-Host ($returnString.SubString(0,1023))
    } else {
        Write-Host $returnString   
    }   
}

#if ($countCritical -gt 0 -or $countOptional -gt 0) {
#	Start-Process "wuauclt.exe" -ArgumentList "/detectnow" -WindowStyle Hidden
#}

if ($countCritical -gt 0) {
	exit $returnStateCritical
}

if ($countOptional -gt 0) {
	exit $returnStateOptionalUpdates
}

if ($countHidden -gt 0) {
	Write-Host "OK - $countHidden hidden updates."
	exit $returnStateOK
}

Write-Host "UNKNOWN script state."
exit $returnStateUnknown
