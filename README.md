# VNX-Graphite
Collects performance and capacity data from VNX arrays and sends them to Graphite using PowerShell

Prerequisites:

.Requires performance analyzer for VNX arrays, with recurring archive (NAR) creation

.Requires Naviseccli connection to arrays

.Requires Graphite-PowerShell-Functions module created by MattHodge https://github.com/MattHodge/Graphite-PowerShell-Functions

Scope and Server Configuration:

Graphite settings configured in the vnxmetrics.xml
Scopes and Metrics can be selected by setting them to 'True' in the vnxmetrics.xml
(example  <Scope Type = "RAID Group" Enabled = "True">)

Using the script:

Script uses naviseccli to query for capacity data, and to retrieve the the latest NAR file
Script converts the NAR to XML, and then queries it for selected performance data. It converts this data to a format required for Graphite, and sends it to the Graphite server using the Send-GraphiteMetric function written by Matt Hodge, as listed above.
NAR archives can be created after a minimum of 10 data points. At 5 min intervals, this is once every 50 minutes. More aggressive polling intervals may result in a performance hit on the array.

Parameters:

        .PARAMETER arrayName
            The name of the VNX array, ex. sealb1vnx01. The script will add the "a" to the end of the array name to pull data.        
        .PARAMETER narPath
            The folder where the Nar file gets retrieved to. Subfolders based on arrayName will be created to move collected Nars to.      
        .PARAMETER logPath
            The full path to the log file for the script. If not determined, it will default to c:\it\logs\vnxmetrics_graphite.log

Use:

 .\vnxmetrics_graphite.ps1 -arrayName vnxarray01 -narPath c:\it\nar -logPath c:\it\logs\vnxmetrics_graphite.log
