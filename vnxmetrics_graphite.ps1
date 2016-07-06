    <#

        .DESCRIPTION
            Gets metrics from VNX arrays, and sends them to Graphite.
            This is accomplished by retrieving NAR files from the arrays, converting them to XML, then sending them to a Graphite server.
            It also uses Naviseccli to pull capacity information and send it to Graphite.
            An XML file named vnxmetrics.xml determines which scopes and metrics to gather, as well as Graphite server settings.
        .PARAMETER arrayName
            The name of the VNX array (not the SP). The script will add the "a" to the end of the array name to pull data.        
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
        #create new object for building metric paths
        $capObjs = @()
        $capObj = New-Object -TypeName psobject
        $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value ""
        $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value ""
        $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value ""
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
            #Get current date time in Unix time
            $uTime = [uint64]([datetime](get-date).ToUniversalTime() - $unixEpochStart).TotalSeconds
                    Write-Host "Gathering Capacity Payload, this may take awhile..."
                    Write-Log -LogPath $logPath -LineValue "Gathering Capacity Payload" -TimeStamp
                #Get capacity info for each pool, build metric paylod to send to graphite.
                foreach ($pool in $poolnames){
                    $uCap = naviseccli -h $spa storagepool -list -name $pool -UserCap
                    $userCap = [int]($uCap | ?{$_ -match "User Capacity \(GBs\)"}).split(":")[-1]
                    $userCaps += $userCap
                    $mpath = $mroot + $arrayName + ".Capacity.Pool." + $pool + ".User_Capacity"             
                    $mValue = $userCap
                    $capObj = New-Object -TypeName psobject
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $capObjs += $capobj
                    $cCap = naviseccli -h $spa storagepool -list -name $pool -ConsumedCap
                    $consumeCap = [int]($cCap | ?{$_ -match "Consumed Capacity \(GBs\)"}).split(":")[-1]            
                    $consumeCaps += $consumeCap
                    $mpath = $mroot + $arrayName + ".Capacity.Pool." + $pool + ".Consumed_Capacity"
                    $mValue = $consumeCap
                    $capObj = New-Object -TypeName psobject
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $capObjs += $capobj
                    $sCap = naviseccli -h $spa storagepool -list -name $pool -SubscribedCap                                   
                    $prcntSub = [int]($sCap | ?{$_ -match "Percent Subscribed"}).split(":")[-1]
                    $mpath = $mroot + $arrayName + ".Capacity.Pool." + $pool + ".Percent_Subscribed"
                    $mValue = $prcntSub
                    $capObj = New-Object -TypeName psobject
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $capObjs += $capobj
                    Write-Host "$pool total capacity = $userCap, consumed capacity = $consumeCap, percent subscribed = $prcntSub"
                    }      
        $script:totalUserCap = ($usercaps | Measure-Object -Sum).Sum
        $script:totalConsumeCap = ($consumeCaps | Measure-Object -Sum).Sum
                    $mPath = $mRoot + $arrayName + ".Capacity.Total_Capacity"
                    [int64]$mValue = $totalUserCap
                    $capObj = New-Object -TypeName psobject
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $capObjs += $capobj
                    $mPath = $mRoot + $arrayName + ".Capacity.Allocated_Capacity"
                    [int64]$mValue = $totalConsumeCap
                    $capObj = New-Object -TypeName psobject
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $capObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $capObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $capObjs += $capobj
        $script:capObjs = $capObjs
        Write-Log -LogPath $logPath -LineValue "Pools: $poolnames"
        Write-Log -LogPath $logPath -LineValue "Total capacity: $totalUserCap, Used Capacity: $totalConsumeCap"
        }
}

function Send-v2_BulkGraphiteMetrics
{
<#
    .Synopsis
        Sends several Graphite Metrics to a Carbon server with one request. Bulk requests save a lot of resources for Graphite server.
        Modified from Send-BulkGraphiteMetrics function to permit sending bulk metrics from an array, without a separate Unix time requirement.
        This mod was required to permit sending past timestamps, as collected through the NAR file, as opposed to current time stamp used by the default function.

    .Description
        This function takes an array with a metric path, value, and timestamp, and sends them to a Graphite server.

    .Parameter CarbonServer
        The Carbon server IP or address.

    .Parameter CarbonServerPort
        The Carbon server port. Default is 2003.

    .Parameter Metrics
        Array containing the following: MetricPath, MetricValue, Timestamp

    .Parameter UnixTime
        The the unix time stamp of the metrics being sent the Graphite Server. 
        No longer required/Do not use; this will most likely break if used. UnixTime variable should be in the Metrics array.

    .Parameter DateTime
        The DateTime object of the metrics being sent the Graphite Server. This does a direct conversion to Unix time without accounting for Time Zones. If your PC time zone does not match your Graphite servers time zone the metric will appear on the incorrect time.
        No longer required/Do not use; this will most likely break if used. Time is gathered from the NAR.

    .Example
        Send-v2_BulkGraphiteMetrics -CarbonServer myserver.local -CarbonServerPort 2003 -Metrics $perfObjs
        This sends all metrics in the $perfObjs array to the specified carbon server.


    .Notes
        NAME:      Send-BulkGraphiteMetrics
        AUTHOR:    Alexey Kirpichnikov
        Modified:  Jeff Peacock 

#>
    param
    (
        [CmdletBinding(DefaultParametersetName = 'Date Object')]
        [parameter(Mandatory = $true)]
        [string]$CarbonServer,

        [parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$CarbonServerPort = 2003,

        [parameter(Mandatory = $true)]
        [array]$Metrics,

        [Parameter(Mandatory = $false,
                   ParameterSetName = 'Epoch / Unix Time')]
        [ValidateRange(1, 99999999999999)]
        [string]$UnixTime,

        [Parameter(Mandatory = $true,
                   ParameterSetName = 'Date Object')]
        [datetime]$DateTime,

        # Will Display what will be sent to Graphite but not actually send it
        [Parameter(Mandatory = $false)]
        [switch]$TestMode,

        # Sends the metrics over UDP instead of TCP
        [Parameter(Mandatory = $false)]
        [switch]$UDP
    )

    # If Received A DateTime Object - Convert To UnixTime
    if ($DateTime)
    {
        $utcDate = $DateTime.ToUniversalTime()
        
        # Convert to a Unix time without any rounding
        [uint64]$UnixTime = [double]::Parse((Get-Date -Date $utcDate -UFormat %s))
    }

    # Create Send-To-Graphite Metric
    [string[]]$metricStrings = @()
    foreach ($key in $Metrics)
    {
        $metricStrings += $key.metricpath + " " + $key.metricvalue + " " + $key.timestamp

        Write-host ("Metric Received: " + $metricStrings[-1])
    }

    $sendMetricsParams = @{
        "CarbonServer" = $CarbonServer
        "CarbonServerPort" = $CarbonServerPort
        "Metrics" = $metricStrings
        "IsUdp" = $UDP
        "TestMode" = $TestMode
    }

    SendMetrics @sendMetricsParams
}

Function Import-XMLConfig
{
<#
    .Synopsis
        Loads the XML Config File for Send-StatsToGraphite.

    .Description
        Loads the XML Config File for Send-StatsToGraphite.

    .Parameter ConfigPath
        Full path to the configuration XML file.

    .Example
        Import-XMLConfig -ConfigPath C:\Stats\Send-PowerShellGraphite.ps1

    .Notes
        NAME:      Convert-TimeZone
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au

#>
    [CmdletBinding()]
    Param
    (
        # Configuration File Path
        [Parameter(Mandatory = $true)]
        $ConfigPath
    )

    [hashtable]$Config = @{ }

    # Load Configuration File
    $xmlfile = [xml]([System.IO.File]::ReadAllText($configPath))

    # Set the Graphite carbon server location and port number
    $Config.CarbonServer = $xmlfile.Configuration.Graphite.CarbonServer
    $Config.CarbonServerPort = $xmlfile.Configuration.Graphite.CarbonServerPort

    # Get the HostName to use for the metrics from the config file
    $Config.NodeHostName = $xmlfile.Configuration.Graphite.NodeHostName
    
    # Set the NodeHostName to ComputerName
    if($Config.NodeHostName -eq '$env:COMPUTERNAME')
    {
        $Config.NodeHostName = $env:COMPUTERNAME
    }

    # Get Metric Send Interval From Config
    [int]$Config.MetricSendIntervalSeconds = $xmlfile.Configuration.Graphite.MetricSendIntervalSeconds

    # Convert Value in Configuration File to Bool for Sending via UDP
    [bool]$Config.SendUsingUDP = [System.Convert]::ToBoolean($xmlfile.Configuration.Graphite.SendUsingUDP)

    # Convert Interval into TimeSpan
    $Config.MetricTimeSpan = [timespan]::FromSeconds($Config.MetricSendIntervalSeconds)

    # What is the metric path

    $Config.MetricPath = $xmlfile.Configuration.Graphite.MetricPath

    # Convert Value in Configuration File to Bool for showing Verbose Output
    [bool]$Config.ShowOutput = [System.Convert]::ToBoolean($xmlfile.Configuration.Logging.VerboseOutput)

    # Create the Performance Counters Array
    $Config.Counters = @()

    # Load each row from the configuration file into the counter array
    foreach ($counter in $xmlfile.Configuration.PerformanceCounters.Counter)
    {
        $Config.Counters += $counter.Name
    }

    # Create the Metric Cleanup Hashtable
    $Config.MetricReplace = New-Object System.Collections.Specialized.OrderedDictionary

    # Load metric cleanup config
    ForEach ($metricreplace in $xmlfile.Configuration.MetricCleaning.MetricReplace)
    {
        # Load each MetricReplace into an array
        $Config.MetricReplace.Add($metricreplace.This,$metricreplace.With)
    }

    $Config.Filters = [string]::Empty;
    # Load each row from the configuration file into the counter array
    foreach ($MetricFilter in $xmlfile.Configuration.Filtering.MetricFilter)
    {
        $Config.Filters += $MetricFilter.Name + '|'
    }

    if($Config.Filters.Length -gt 0) {
        # Trim trailing and leading white spaces
        $Config.Filters = $Config.Filters.Trim()

        # Strip the Last Pipe From the filters string so regex can work against the string.
        $Config.Filters = $Config.Filters.TrimEnd("|")
    }
    else
    {
        $Config.Filters = $null
    }

    # Doesn't throw errors if users decide to delete the SQL section from the XML file. Issue #32.
    try
    {
        # Below is for SQL Metrics
        $Config.MSSQLMetricPath = $xmlfile.Configuration.MSSQLMetics.MetricPath
        [int]$Config.MSSQLMetricSendIntervalSeconds = $xmlfile.Configuration.MSSQLMetics.MetricSendIntervalSeconds
        $Config.MSSQLMetricTimeSpan = [timespan]::FromSeconds($Config.MSSQLMetricSendIntervalSeconds)
        [int]$Config.MSSQLConnectTimeout = $xmlfile.Configuration.MSSQLMetics.SQLConnectionTimeoutSeconds
        [int]$Config.MSSQLQueryTimeout = $xmlfile.Configuration.MSSQLMetics.SQLQueryTimeoutSeconds

        # Create the Performance Counters Array
        $Config.MSSQLServers = @()     
     
        foreach ($sqlServer in $xmlfile.Configuration.MSSQLMetics)
        {
            # Load each SQL Server into an array
            $Config.MSSQLServers += [pscustomobject]@{
                ServerInstance = $sqlServer.ServerInstance;
                Username = $sqlServer.Username;
                Password = $sqlServer.Password;
                Queries = $sqlServer.Query
            }
        }
    }
    catch
    {
        Write-Verbose "SQL configuration has been left out, skipping."
    }

    Return $Config
}

# http://support-hq.blogspot.com/2011/07/using-clause-for-powershell.html
function PSUsing
{
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )

    Try
    {
        &$scriptBlock
    }
    Finally
    {
        if ($inputObject -ne $null)
        {
            if ($inputObject.psbase -eq $null)
            {
                $inputObject.Dispose()
            }
            else
            {
                $inputObject.psbase.Dispose()
            }
        }
    }
}

function SendMetrics
{
    param (
        [string]$CarbonServer,
        [int]$CarbonServerPort,
        [string[]]$Metrics,
        [switch]$IsUdp = $false,
        [switch]$TestMode = $false
    )

    if (!($TestMode))
    {
        try
        {
            if ($isUdp)
            {
                PSUsing ($udpobject = new-Object system.Net.Sockets.Udpclient($CarbonServer, $CarbonServerPort)) -ScriptBlock {
                    $enc = new-object system.text.asciiencoding
                    foreach ($metricString in $Metrics)
                    {
                        $Message += "$($metricString)`n"
                    }
                    $byte = $enc.GetBytes($Message)

                    Write-Verbose "Byte Length: $($byte.Length)"
                    $Sent = $udpobject.Send($byte,$byte.Length)
                }

                Write-Verbose "Sent via UDP to $($CarbonServer) on port $($CarbonServerPort)."
            }
            else
            {
                PSUsing ($socket = New-Object System.Net.Sockets.TCPClient) -ScriptBlock {
                    $socket.connect($CarbonServer, $CarbonServerPort)
                    PSUsing ($stream = $socket.GetStream()) {
                        PSUSing($writer = new-object System.IO.StreamWriter($stream)) {
                            foreach ($metricString in $Metrics)
                            {
                                $writer.WriteLine($metricString)
                            }
                            $writer.Flush()
                            Write-Verbose "Sent via TCP to $($CarbonServer) on port $($CarbonServerPort)."
                        }
                    }
                }
            }
        }
        catch
        {
            $exceptionText = GetPrettyProblem $_
            Write-Error "Error sending metrics to the Graphite Server. Please check your configuration file. `n$exceptionText"
        }
    }
}

function GetPrettyProblem {
    param (
        $Problem
    )

    $prettyString = (Out-String -InputObject (format-list -inputobject $Problem -Property * -force)).Trim()
    return $prettyString
}


Import-Module Graphite-Powershell
#Read the settings file to determine Scopes to include, and the graphite host settings
[xml]$settingsFile = get-content ".\vnxmetrics.xml"
$gServer = $settingsFile.Configuration.Graphite.CarbonServer
$gPort = $settingsFile.Configuration.Graphite.CarbonServerPort
$mRoot = $settingsFile.Configuration.Graphite.MetricRoot
$validScopes = @()
$validScopes = ($settingsfile.Configuration.Monitor.Scope | ?{$_.Enabled -eq "True"}).Type
#create a new object for creating performance metrics payload.
$perfObjs = @()
$perfObj = New-Object -TypeName psobject
$perfObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value ""
$perfObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value ""
$perfObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value ""

#Create an object to convert time stamps to Unix Time, required for graphite metrics
$unixEpochStart = new-object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)

#If arrayname does not end in A, append it.
if (!($arrayName.EndsWith("a") -or $arrayName.EndsWith("A"))){
$SPA = $arrayName + "a"
$SPB = $arrayName + "b"
} else {
$SPA = $arrayName
}

if (!(Test-Connection $spa)){
Write-Host "No ping response from $spa. Verify name and try again. Exiting script."
Write-Log -LogPath $logPath -LineValue "No ping response from $spa. Exiting script."
exit
}
Write-Log -LogPath $logPath -LineValue "Starting script for array $arrayName with Scopes: $validScopes" -TimeStamp


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
Write-Log -LogPath $logPath -LineValue "Creating perfomance metrics payload." -TimeStamp
write-host "Creating Metrics Payload to send to Graphite. This may take awhile..."
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
                    #Create bulk metrics to send to Graphite
                    $perfObj = New-Object -TypeName psobject
                    $perfObj | Add-Member -MemberType NoteProperty -Name MetricPath -Value "$mpath"
                    $perfObj | Add-Member -MemberType NoteProperty -Name MetricValue -Value $mValue
                    $perfObj | Add-Member -MemberType NoteProperty -Name Timestamp -Value $uTime
                    $perfObjs += $perfObj
                    $i++
                }
            }   
        }
}


#Move the Nar and Xml file to a subdirectory for completed pulls.
$subdir = $narPath + "`\" + $arrayName
if (!(Test-Path -Path $subdir)){
New-Item -ItemType directory -Path "$subdir"
}
Move-Item $narpath\$lastnarA -Destination "$narpath\$arrayname\$lastnarA"
Remove-Item $narAXml

#Get Capacities from array and send to Graphite
Write-Log -LogPath $logPath -LineValue "Performance data complete. Getting capacity information"
Get-Capacity -spa $SPA

#Send payloads to Graphite
Write-Host "Sending data to Graphite"
Write-Log -LogPath $logPath -LineValue "Beginning send of Capacity Payload to Graphite" -TimeStamp
Send-v2_BulkGraphiteMetrics -CarbonServer $gServer -CarbonServerPort 2003 -Metrics $capObjs
Write-Log -LogPath $logPath -LineValue "Beginning send of Performance Payload to Graphite" -TimeStamp
Send-v2_BulkGraphiteMetrics -CarbonServer $gServer -CarbonServerPort 2003 -Metrics $perfObjs
Write-Log -LogPath $logPath -LineValue "Sending metrics complete" -TimeStamp
$capfile = "$subdir\capMetrics_" + (get-date -f MM-dd-yyyy_HH_mm_ss) + ".csv"  
$capObjs | Export-Csv -verbose $capfile 
$perffile = "$subdir\perfMetrics_" + (get-date -f MM-dd-yyyy_HH_mm_ss) + ".csv"  
$perfObjs | Export-Csv -Verbose $perffile 
Write-Host 'Script Complete'

#End Script
