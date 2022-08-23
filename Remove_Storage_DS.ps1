$inScope = @()
do {
    $data = $(
        Search-AzGraph -Query "resources | where type =~ 'microsoft.storage/storageaccounts' 
         " `
            -ManagementGroup "1f61b0d8-cp39-44c6-997d-e0250ea685a4" `
            -SkipToken $($data.SkipToken ?? $Null) `
            -First 500
    );


    $inScope += $data.Data.ResourceId

} while ( $Null -ne $data.SkipToken )


$diagnosticSetting = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$enabledTypes = @("", "blobServices", "fileServices", "queueServices", "tableServices")
$diagnosticName = "setbyCPEpolicy_SentinelLAW"
#$diagnosticName = "setbySKTest992policy_SentinelLAW"

$inScope | ForEach-Object -Parallel {
    $syncDiagnostics = $USING:diagnosticSetting
    

    ForEach ($type in $USING:enabledTypes) {


        $LOCAL:resourceId = "$_/$type$($type -ne '' ? '/default' : '')"

        $LOCAL:Diag = Get-AzDiagnosticSetting -ResourceId $LOCAL:resourceId `
            -WarningAction "SilentlyContinue" |
        Where-Object { $_.Name -eq $USING:diagnosticName }

        
        if ($LOCAL:Diag -ne $Null) {
            [void]$syncDiagnostics.Add($_)

            #Extract RG Name, Subscription ID
            $LOCAL:resarray = ($_).Split('/') 
            $LOCAL:RGind = 0..($LOCAL:resarray.Length - 1) | where { $LOCAL:resarray[$_] -eq 'resourcegroups' }
            $LOCAL:Subind = 0..($LOCAL:resarray.Length - 1) | where { $LOCAL:resarray[$_] -eq 'subscriptions' }
            $LOCAL:resgroup = $LOCAL:resarray.get($LOCAL:RGind + 1)
            $LOCAL:subid = $LOCAL:resarray.get($LOCAL:Subind + 1)


            #check lock exist on RG name
            Set-AzContext -Subscription $LOCAL:subid -WarningAction "SilentlyContinue"
            $LOCAL:lockdet = Get-AzResourceLock -ResourceGroupName $LOCAL:resgroup

            if ($LOCAL:lockdet -ne $Null) {

                #Remove the lock
                Remove-AzResourceLock -LockId $($LOCAL:lockdet.LockId) -Force 

                #Remove DS
                Remove-AzDiagnosticSetting -ResourceId $LOCAL:resourceId `
                    -Name $USING:diagnosticName

                #Add back the lock
                New-AzResourceLock -LockName $($LOCAL:lockdet.Name) `
                    -LockLevel $($LOCAL:lockdet.Properties.level) `
                    -ResourceGroupName $LOCAL:resgroup `
                    -Force

            }
            else {
                #Remove DS
                Remove-AzDiagnosticSetting -ResourceId $LOCAL:resourceId `
                    -Name $USING:diagnosticName

            }
        }
    }
}
