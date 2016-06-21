    <#

        .DESCRIPTION
            Gets metrics from VNX arrays, and sends them to Graphite.
            This is accomplished by retrieving NAR files from the arrays, converting them to XML, then sending them to a Graphite server.
            It also uses Naviseccli to pull capacity information and send it to Graphite.
            An XML file named vnxmetrics.xml determines which scopes and metrics to gather, as well as Graphite server settings.
        .PARAMETER arrayName
            The name of the VNX array, ex. sealb1vnx01. The script will add the "a" to the end of the array name to pull data.        
        .PARAMETER narPath
            The folder where the Nar file gets retrieved to. Subfolders based on arrayName will be created to move collected Nars to.      
        .PARAMETER logPath
            The full path to the log file for the script. If not determined, it will default to c:\it\logs\vnxmetrics_graphite.log
        .EXAMPLE
           .\vnxmetrics_graphite.ps1 -arrayName VNXarray01 -narPath c:\it\nar -logPath c:\it\logs\vnxmetrics_graphite.log
        .Author
            jpeacock@
            Created 6/21/16

         .Requires
            Naviseccli connection to arrays
            Graphite-PowerShell-Functions module created by MattHodge https://github.com/MattHodge/Graphite-PowerShell-Functions     
    #>
   
   param
    (
        [CmdletBinding()]
        [parameter(Mandatory = $true)]
        [string]$arrayName,
        [parameter(Mandatory = $true)]
        [ValidateScript({(Test-Path $_ -pathtype container)})]
        [string]$narPath,
        [parameter(Mandatory = $false)]
        [string]$logPath = "c:\it\logs\vnxmetrics_graphite.log"
        )


Function Write-Log
{
    <#
	
	.Description  
		Writes a new line to the end of the specified log file
    
	.EXAMPLE
        Write-Log -LogPath "C:\Windows\Temp\Test_Script.log" -LineValue "This is a new line which I am appending to the end of the log file."
    #>
 
    [CmdletBinding()]
 
    Param (
	[Parameter(Mandatory=$true)]
	[string]$LogPath, 
	[Parameter(Mandatory=$true)]
	[string]$LineValue,
	[Parameter(Mandatory=$false)]
	[switch]$TimeStamp
	
	)
 
	
    Process
		{
			$parentLogPath = Split-Path -Parent $LogPath
			if (!(Test-Path $parentLogPath))
			{
				New-Item -ItemType directory -Path $parentLogPath
			}
			$time = get-date -Uformat "%D %T"	
		
		
				if ($timestamp -eq $True)
				{
					Add-Content -Path $LogPath -Value "$time`: $LineValue"
				}
				else
				{
	     		   Add-Content -Path $LogPath -Value "$LineValue"
				}
	        #Write to screen for debug mode
	        Write-Debug $LineValue
	    }
}

Function Get-Capacity 
{
<#
	.Description  
		Uses Navisec to get total and used capacities from a VNX array
    
	.EXAMPLE
        Get-Capacity -spa arraySPA
    #>
    param
        (
            [CmdletBinding()]
            [parameter(Mandatory = $true)]
            [string]$spa
            )

    Process{
        #Get pool listing from navisec
        $spools = @()
        $poolnames = @()
        $spools = naviseccli -h $spa storagepool -list | ?{($_ -match "Pool Name")}
            foreach ($pool in $spools){
                $poolname = $pool.split(":")[-1].trim()
                $poolnames += $poolname
                }
        #Total Capacity is refrenced as User Capacity in Navisec. Allocated Capacity is refrenced as Consumed Capacity.
        $userCaps = @()
        $consumeCaps = @()
            foreach ($pool in $poolnames){
            $uCap = naviseccli -h $spa storagepool -list -name $pool -UserCap
            $userCap = [int]($uCap | ?{$_ -match "User Capacity \(GBs\)"}).split(":")[-1]
            $userCaps += $userCap
            $cCap = naviseccli -h $spa storagepool -list -name $pool -ConsumedCap
            $consumeCap = [int]($cCap | ?{$_ -match "Consumed Capacity \(GBs\)"}).split(":")[-1]
            Write-Host "$pool total capacity = $userCap, consumed capacity = $consumeCap"
            $consumeCaps += $consumeCap
            }
        $script:totalUserCap = ($usercaps | Measure-Object -Sum).Sum
        $script:totalConsumeCap = ($consumeCaps | Measure-Object -Sum).Sum
        Write-Log -LogPath $logPath -LineValue "Pools: $poolnames"
        Write-Log -LogPath $logPath -LineValue "Total capacity: $totalUserCap, Used Capacity: $totalConsumeCap"
        }
}


#Read the settings file to determine Scopes to include, and the graphite host settings
[xml]$settingsFile = get-content ".\vnxmetrics.xml"
$gServer = $settingsFile.Configuration.Graphite.CarbonServer
$gPort = $settingsFile.Configuration.Graphite.CarbonServerPort
$mRoot = $settingsFile.Configuration.Graphite.MetricRoot
$validScopes = @()
$validScopes = ($settingsfile.Configuration.Monitor.Scope | ?{$_.Enabled -eq "True"}).Type

#Create an object to convert time stamps to Unix Time, required for graphite metrics
$unixEpochStart = new-object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)

#Determine Array, this will be a mandatory parameter later.
$SPA = $arrayName + "a"
$SPB = $arrayName + "b"
if (!(Test-Connection $spa)){
Write-Host "No ping response from $spa. Verify name and try again. Exiting script."
Write-Log -LogPath $logPath -LineValue "No ping response from $spa. Exiting script."
exit
}
Write-Log -LogPath $logPath -LineValue "Starting script for array $arrayName with Scopes: $validScopes" -TimeStamp

#Set location to retrieve NAR files to.
#$narpath = "c:\it\nar"
#Retrieve the latest NAR file from the array
$narlistA = naviseccli -h $spa analyzer -archive -list
$lastnarA = $narlistA[-1].Split(" ")[-1]
if ((!(Test-Path -Path "$narpath\$lastnarA") -and !(Test-Path -Path "$narpath\$arrayname\$lastnarA")))
{
Write-Host "Retrieving $lastnarA"
naviseccli -h $spa analyzer -archiveretrieve -file $lastnarA -location $narpath
} else {
Write-Host "$lastnarA has already been retrieved, attempting pull of new NAR"
Write-Log -LogPath $logPath -LineValue "$lastnarA has already been retrieved, attempting pull of new NAR"
#As retrieving a NAR file can cause a new NAR to be created, we retrieve and delete the already completed NAR, and check for a new one.
naviseccli -h $spa analyzer -archiveretrieve -file $lastnarA -location $narpath
Remove-Item -Path $narpath\$lastnarA
Start-Sleep 15
$narlistA = naviseccli -h $spa analyzer -archive -list
$lastnarA = $narlistA[-1].Split(" ")[-1]
if ((!(Test-Path -Path "$narpath\$lastnarA") -and !(Test-Path -Path "$narpath\$arrayname\$lastnarA")))
{
Write-Host "New Nar found, Retrieving $lastnarA"
Write-Log -LogPath $logPath -LineValue "New Nar found, Retrieving $lastnarA"
naviseccli -h $spa analyzer -archiveretrieve -file $lastnarA -location $narpath
} else {
Write-Host "No new NAR found, exiting this script"
Write-Log -LogPath $logPath -LineValue "No new NAR found, exiting this script"
exit
}
}

Write-Host "Analyzing data..."
#Convert the NAR to XML, and import the data.
naviseccli -h $spa analyzer -archivedump -data "$narpath\$lastnarA" -xml -out ("$narpath\$lastnarA".Split(".")[0] + ".xml")
$narAXml = "$narpath\" + $lastnarA.Split(".")[0] + ".xml"
[xml]$aXml = Get-Content "$narAXml"
#As the actual metric values are listed as a type #text, which freaks Powershell out, create a variable to eliminate the '#'
$text = "`#text"
#Get count of unique data samples (timestamps) in NAR. This will determine how many samples to loop through in the script.
$sampleCount = $aXml.archivedump.archivefile.object[0].data.sample.count
$firstStamp = ($aXml.archivedump.archivefile.object[0].data.sample[0].value | ?{$_.type -match "Poll"} | select `#text | ?{$_}).$text
$lastStamp = ($aXml.archivedump.archivefile.object[0].data.sample[-1].value | ?{$_.type -match "Poll"} | select `#text | ?{$_}).$text
Write-Log -LogPath $logPath -LineValue "$sampleCount total samples between $firstStamp and $lastStamp"
Write-Log -LogPath $logPath -LineValue "Sending metrics to Graphite" -TimeStamp

Write-Host "Sending metrics to Graphite. This may take awhile"
#Begin the work
#Loop through each scope set to True in the settings file.
foreach ($Scope in $validScopes){
    #for each scope, loop through each metric set to True in the settings file
    $validMetricTypes = @()
    $validMetricTypes = (($settingsfile.Configuration.Monitor.Scope | ?{$_.Type -eq "$Scope"}).Metric | ?{$_.Enabled -eq "True"}).Name
    #get the items/names of each object in the scope (ex. each pool name, each Raid Group name, etc.)
    $items = @()
    $items = ($aXml.archivedump.archivefile.object | ?{($_.type -eq "$Scope")}).name
        foreach ($item in $items){
            #loop through each item, getting the selected metrics and values for each unique data sample/time stamp
            foreach ($metric in $validMetricTypes){
                $i = 0
                while ($i -le ($sampleCount -1)) {
                    $scopeInfo = ($aXml.archivedump.archivefile.object | ?{($_.type -eq "$Scope") -and ($_.name -match "$item")}).data.sample[$i].value
                    #to create a valid graphite scope name, remove spaces (ex. 'RAID Group' = 'RAIDGroup')
                    $scopeName = $scope.trim() -replace (" ","")
                    #to create a valid item name and graphite metric path, we need to remove spaces again (ex. 'Raid Group 3' = 'Raid_Group_3')
                    $itemName = (($scopeInfo | ?{$_.type -match "Object Name"} | select `#text | ?{$_}).$text) -replace (" ","_")
                    #Convert timestamp to Unix, required for graphite
                    [datetime]$pollTime = ($scopeInfo | ?{$_.type -match "Poll"} | select `#text | ?{$_}).$text
                    $uTime = [uint64]([datetime]$pollTime.ToUniversalTime() - $unixEpochStart).TotalSeconds
                    #to create a valid metric name for graphite, we need to remove spaces. This time we replace them with underscores (ex. 'Read Bandwidth' = 'Read_Bandwidth')
                    $metricName = $metric.trim() -replace (" ","_")
                    #trailing spaces are the devil.
                    [int64]$metricValue = ($scopeInfo | ?{$_.type -eq "$metric" -or $_.type -eq "$metric "} | select `#text | ?{$_}).$text
                    $mName = $itemName + "." + $metricName
                    $mPath = $mRoot + $arrayName + "." + $scopeName + "." + $mName
                    $mValue = $metricValue
                    #Send the data to Graphite
                    write-host "Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime"
                    Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime
                    $i++
                }
            }   
        }
}


#Move the Nar and Xml file to a subdirectory for completed pulls.
if (!(Test-Path -Path "$narpath\$arrayame")){ 
New-Item -ItemType directory -Path "$narpath\$arrayname"
}
Move-Item $narpath\$lastnarA -Destination "$narpath\$arrayname\$lastnarA"
Move-Item $narAXml -Destination "$narpath\$arrayname\"

#Get Capacities from array and send to Graphite
Write-Log -LogPath $logPath -LineValue "Performance data complete. Getting capacity information"
Get-Capacity -spa $SPA
#Get current date time in Unix time
$uTime = [uint64]([datetime](get-date).ToUniversalTime() - $unixEpochStart).TotalSeconds
#Define Metric path for Graphite
$mPath = $mRoot + $arrayName + ".Capacity.Total_Capacity"
[int64]$mValue = $totalUserCap
write-host "Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime"
Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime
$mPath = $mRoot + $arrayName + ".Capacity.Allocated_Capacity"
[int64]$mValue = $totalConsumeCap
write-host "Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime"
Send-GraphiteMetric -CarbonServer $gserver -CarbonServerPort 2003 -MetricPath $mPath -MetricValue $mValue -UnixTime $uTime
Write-Log -LogPath $logPath -LineValue "Sending metrics complete" -TimeStamp
Write-Host 'Script Complete'


#End Script
