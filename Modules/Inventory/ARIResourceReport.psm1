<#
.Synopsis
Main module for Excel Report Building

.DESCRIPTION
This module is the main module for building the Excel Report.

.Link
https://github.com/microsoft/ARI/Modules/Inventory/ARIResourceReport.psm1

.COMPONENT
This powershell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 4.0.1
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
Function Build-AzureResourceReport {
    Param($Subscriptions,
    $ExtractionRuntime,
    $Resources,
    $SecurityCenter,
    $File,
    $DDFile,
    $SkipDiagram,
    $RunLite,
    $PlatOS,
    $InTag,
    $SkipAPIs,
    $SkipPolicy,
    $SkipAdvisory,
    $Automation,
    $Debug)

    if ($Debug.IsPresent)
        {
            $DebugPreference = 'Continue'
            $ErrorActionPreference = 'Continue'
        }
    else
        {
            $ErrorActionPreference = "silentlycontinue"
        }

    $ReportingRunTime = Measure-Command -Expression {

        #### Generic Conditional Text rules, Excel style specifications for the spreadsheets and tables:
        $TableStyle = "Light19"
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Excel Table Style used: ' + $TableStyle)

        Write-Progress -activity 'Azure Inventory' -Status "21% Complete." -PercentComplete 21 -CurrentOperation "Starting to process extraction data.."


        <######################################################### IMPORT UNSUPPORTED VERSION LIST ######################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Importing List of Unsupported Versions.')

        $Unsupported = Get-ARIUnsupportedData -Debug $Debug

        $DataActive = ('Azure Resource Inventory Reporting (' + ($Resources.count) + ') Resources')

        <######################################################### RESOURCE GROUP JOB ######################################################################>

        if ($Automation.IsPresent)
            {
                $SmaResources = Start-ARIAutResourceJob -Resources $Resources -Subscriptions $Subscriptions -InTag $InTag -Unsupported $Unsupported
            }
        else
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Resource Jobs.')

                $DebugEnvSize = Start-ARIResourceJobs -Resources $Resources -Subscriptions $Subscriptions -InTag $InTag -Unsupported $Unsupported -Debug $Debug
            }

        <############################################################## RESOURCES LOOP CREATION #############################################################>

        if (!$Automation.IsPresent)
            {
                if($DebugEnvSize -in ('Large','Enormous'))
                {
                    Clear-Variable Resources
                    [System.GC]::GetTotalMemory($true) | out-null
                }

                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')
                Write-Progress -activity $DataActive -Status "Processing Inventory" -PercentComplete 0
                $c = 0

                $JobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name

                while (get-job -Name $JobNames | Where-Object { $_.State -eq 'Running' }) {
                    $jb = get-job -Name $JobNames
                    $c = (((($jb.count - ($jb | Where-Object { $_.State -eq 'Running' }).Count)) / $jb.Count) * 100)
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Jobs Still Running: '+[string]($jb | Where-Object { $_.State -eq 'Running' }).count)
                    $c = [math]::Round($c)
                    Write-Progress -Id 1 -activity "Processing Resource Jobs" -Status "$c% Complete." -PercentComplete $c
                    Start-Sleep -Seconds 5
                }
                Write-Progress -Id 1 -activity "Processing Resource Jobs" -Status "100% Complete." -Completed

                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Jobs Compleated.')

                $SmaResources = @()

                Foreach ($Job in $JobNames)
                    {
                        $TempJob = Receive-Job -Name $Job
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Job '+ $Job +' Returned: ' + ($TempJob.values | Where-Object {$_ -ne $null}).Count + ' Resource Types.')
                        $SmaResources += $TempJob
                    }
            }

        <############################################################## REPORTING ###################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Resource Reporting.')

        Start-ARIResourceReporting -InTag $InTag -file $file -SmaResources $SmaResources -TableStyle $TableStyle -Unsupported $Unsupported -DebugEnvSize $DebugEnvSize -DataActive $DataActive -Debug $Debug

        <################################################################### EXTRA REPORTS ###################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Default Data Reporting.')

        Start-ARIExtraReports -File $File -QuotaUsage $QuotaUsage -SecurityCenter $SecurityCenter -SkipPolicy $SkipPolicy -SkipAdvisory $SkipAdvisory -TableStyle $TableStyle -Debug $Debug

        <################################################################### CHARTS ###################################################################>

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Generating Overview sheet (Charts).')

    }

    Write-Progress -activity 'Azure Resource Inventory Reporting Charts' -Status "15% Complete." -PercentComplete 15 -CurrentOperation "Invoking Excel Chart's Module."

    Build-ARIExcelChart -File $File -TableStyle $TableStyle -PlatOS $PlatOS -Subscriptions $Subscriptions -ExtractionRunTime $ExtractionRuntime -ReportingRunTime $ReportingRunTime -RunLite $RunLite -Debug $Debug

    [System.GC]::GetTotalMemory($true) | out-null

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Finished Charts Phase.')

    Write-Progress -activity 'Azure Resource Inventory Reporting Charts' -Status "100% Complete." -Completed

    if(!$SkipDiagram.IsPresent)
    {
        Write-Progress -activity 'Diagrams' -Status "Completing Diagram" -PercentComplete 70 -CurrentOperation "Consolidating Diagram"

        while (get-job -Name 'DrawDiagram' | Where-Object { $_.State -eq 'Running' }) {
            Write-Progress -Id 1 -activity 'Processing Diagrams' -Status "50% Complete." -PercentComplete 50
            Start-Sleep -Seconds 2
        }
        Write-Progress -Id 1 -activity 'Processing Diagrams'  -Status "100% Complete." -Completed

        Write-Progress -activity 'Diagrams' -Status "Closing Diagram File" -Completed
    }

    Get-Job | Wait-Job | Remove-Job
}