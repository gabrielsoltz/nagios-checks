###############################################################################
# Windows PowerShell Skript to get WSUS statistics
# output readable by NRPE for Nagios monitoring
#
# FORK FROM: http://www.monitoring-portal.org/wbb/index.php?page=Thread&threadID=16424
###############################################################################


# Variables - set these to fit your needs
###############################################################################
# The server name of your WSUS server
$serverName = 'localhost'

# use SSL connection?
$useSecureConnection = $False

# the port number of your WSUS IIS website
$portNumber = 8530

# warn if a computer has not contacted the server for ... days
$daysBeforeWarn = 14



# Script - don't change anything below this line!
###############################################################################

# load WSUS framework
[void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")   

# connect to specified WSUS server
# see here for information of the IUpdateServer class
# -> http://msdn.microsoft.com/en-us/library/microsoft.updateservices.administration.iupdateserver(VS.85).aspx
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($serverName, $useSecureConnection, $portNumber)   

# get general status information
# see here for more infos about the properties of GetStatus()
# -> http://msdn.microsoft.com/en-us/library/microsoft.updateservices.administration.updateserverstatus_properties(VS.85).aspx
$status = $wsus.GetStatus()
$totalComputers = $status.ComputerTargetCount

# computers with errors
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed
$computersWithErrors = $wsus.GetComputerTargetCount($computerTargetScope)

# computers with needed updates
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::NotInstalled -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::InstalledPendingReboot -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Downloaded
$computerTargetScope.ExcludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed
$computersNeedingUpdates = $wsus.GetComputerTargetCount($computerTargetScope)

# computers without status
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Unknown
$computerTargetScope.ExcludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::NotInstalled -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::InstalledPendingReboot -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Downloaded
$computersWithoutStatus = $wsus.GetComputerTargetCount($computerTargetScope)



# computers that are OK
$computersOK = $totalComputers - $computersWithErrors - $computersNeedingUpdates - $computersWithoutStatus



# needed, but not approved updates
$updateScope = new-object Microsoft.UpdateServices.Administration.UpdateScope
$updateScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved
$updateServerStatus = $wsus.GetUpdateStatus($updateScope, $False)
$updatesNeededByComputersNotApproved = $updateServerStatus.UpdatesNeededByComputersCount

# computers that did not contact the server in $daysBeforeWarn days
$timeSpan = new-object TimeSpan($daysBeforeWarn, 0, 0, 0)
$computersNotContacted = $wsus.GetComputersNotContactedSinceCount([DateTime]::UtcNow.Subtract($timeSpan))

# computers in the "not assigned" group
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computersNotAssigned = $wsus.GetComputerTargetGroup([Microsoft.UpdateServices.Administration.ComputerTargetGroupId]::UnassignedComputers).GetComputerTargets().Count

# output and return code
# 0: OK
# 1: WARNING
# 2: CRITICAL
# 3: UNKNOWN
$returnCode = 0
$output = ''

if ($computersNeedingUpdates -gt 0) {
	$returnCode = 1
	$output = "$computersNeedingUpdates PC Desactualizadas"
}

if ($computersWithErrors -gt 0) {
	$returnCode = 2
	if ($output -ne '') {
		$output = $output + ', '
	}
	$output = $output + "$computersWithErrors PC Con Errores"
}

if ($computersNotContacted -gt 0) {
	$returnCode = 2
	if ($output -ne '') {
		$output = $output + ', '
	}
	$output = $output + "$computersNotContacted PC Sin Contacto ($daysBeforeWarn d)"
}

if ($computersNotAssigned -gt 0) {
	$returnCode = 2
	if ($output -ne '') {
		$output = $output + ', '
	}
	$output = $output + "$computersNotAssigned PC Sin Asignar"
}

if ($updatesNeededByComputersNotApproved -gt 0) {
	$returnCode = 2
	if ($output -ne '') {
		$output = $output + ', '
	}
	$output = $output + "$updatesNeededByComputersNotApproved Upd. S/A"
}

if ($output -eq '') {
	$output = 'Todas las Computadoras Asignadas, Activas y Al dia.'
}

$output

# append performance data
'|' + "'PC Desactualizadas'=$computersNeedingUpdates;;;0;$totalComputers"
'|' + "'PC Con Errores'=$computersWithErrors;"
"'PC Sin Estatus'=$computersWithoutStatus;"
"'PC OK'=$computersOK;"

$host.SetShouldExit($returnCode)
exit $returnCode
