param(
    [parameter(mandatory=$true)]
    [string]$ScheduleName,

    [parameter(mandatory=$true)]
    [string]$VariableName = "ConfigScheduleUpdate",

    [parameter(mandatory=$false)]
    [string]$ServerListVariableName = $null,

    [parameter(mandatory=$false)]
    [string]$Subscription,

    [parameter(mandatory=$false)]
    [string]$Root = "",

	[parameter(mandatory=$true)]
    [string]$SLName
    )

<#  Global State Configuration Start #>
#******************************************************************************
<#  
    Script Initialization Start 
    This script doesn't need to inherit Global Variable from the parent context. We initialize it as a new Hash object and share between functions to simplify coding.
#>
$Global:ConfigScheduleUpdate = @{}
#$Global:ConfigScheduleUpdate['RunOnAzure'] = 0
$Global:ConfigScheduleUpdate['JsonData'] = $null
$Global:Serverlist = @()
#$errorActionPreference = "Stop"
#******************************************************************************
try
{
    #========Login and load configure============
    #if ("AzureAutomation/" -eq $env:AZUREPS_HOST_ENVIRONMENT) {
        Write-Output "This runbook "prepareserverlist" is running on the Worker: $env:computername"
        # Connect-AzAccount -Identity #-Subscription $Subscription
        #$Global:ConfigScheduleUpdate['RunOnAzure'] = 1
        $content = Get-AutomationVariable -Name $VariableName
        $Global:ConfigScheduleUpdate.JsonData = $content | ConvertFrom-Json       
		     
	<#else{
        Set-StrictMode -Version Latest
        $here = if($MyInvocation.MyCommand.PSObject.Properties.Item("Path") -ne $null){(Split-Path -Parent $MyInvocation.MyCommand.Path)}else{$(Get-Location).Path}
        pushd $here
        Write-Output "This script ConfigScheduleUpdate running locally"
        if(Test-Path "$here\azurecontext.json"){
            $AzureContext = Import-AzContext -Path "$here\azurecontext.json"
        }else{
            $AzureContext = Connect-AzAccount -Subscription $Subscription -Identity -ErrorAction Stop
            Save-AzContext -Path "$here\azurecontext.json"
        }
        if([string]::IsNullOrEmpty($VariableName)){
            Write-Output "Load default config from $here\ConfigScheduleUpdate.json "
            $Global:ConfigScheduleUpdate.JsonData = (Get-content -Path "$here\ConfigScheduleUpdate.json") | ConvertFrom-Json
        }else{
            Write-Output "Load config from $VariableName"
            ##$Global:ConfigScheduleUpdate.JsonData = (Get-content -Path $VariableName) | ConvertFrom-Json
            $content = Get-AutomationVariable -Name $VariableName
            $Global:ConfigScheduleUpdate.JsonData = $content | ConvertFrom-Json  
        }
    } #>
    $s = $null
    foreach($schedule in $Global:ConfigScheduleUpdate.JsonData.Schedule){
        if($schedule.ScheduleName -ieq $ScheduleName){
            $s = $schedule
            break   
        }        
    }
   #======== Static serverlist ============
    $servers = @()
    if($s -ne $null){
          #======== get servers from ServerListVariable ==========
	#if($Global:ConfigScheduleUpdate.RunOnAzure -eq 1){
            if(![string]::IsNullOrEmpty($ServerListVariableName)){
                Write-Output "Get automation variable from $ServerListVariableName"
                $Global:ConfigScheduleUpdate['ServerListVariable'] = Get-AutomationVariable -Name $ServerListVariableName
                ###$s.ScheduleName = "$($s.ScheduleName)_$($ServerListVariableName)"
				$servers += $Global:ConfigScheduleUpdate['ServerListVariable'].split("`n")
            }elseif(![string]::IsNullOrEmpty($s.ServerListVariableName)){
			    Write-Output "Get automation variable from $($s.ServerListVariableName)"
                $Global:ConfigScheduleUpdate['ServerListVariable'] = Get-AutomationVariable -Name $($s.ServerListVariableName)
                ###$s.ScheduleName = "$($s.ScheduleName)_$($s.ServerListVariableName)"
				$servers += $Global:ConfigScheduleUpdate['ServerListVariable'].split("`n")
        	}
            #$servers = ($Global:ConfigScheduleUpdate['ServerListVariable'].split("`n") -join ',')
    	 
         Write-Output "Processing $($servers) under Variable: $($ServerListVariableName) AutomationAccountName: $($s.AutomationAccountName) ResourceGroupName: $($s.ResourceGroupName) Subscription: $($s.Subscription)"
        
          #======== get servers from serverlist =============
         if(![string]::IsNullOrEmpty($s.ServerList) -and $s.ServerList.GetType().BaseType.Name -eq "Array"){
            #$servers = $s.ServerList -join ','
            $servers += $s.ServerList
         }elseif(![string]::IsNullOrEmpty($s.ServerList)){
            $servers += $s.ServerList
         }
		 <#
         if(![string]::IsNullOrEmpty($Global:ConfigScheduleUpdate['ServerListVariable'])){
            if([string]::IsNullOrEmpty($servers)){
                #$servers = ($Global:ConfigScheduleUpdate['ServerListVariable'].split("`n") -join ',')
                $servers += $Global:ConfigScheduleUpdate['ServerListVariable'].split("`n")
             }else{
                #$servers = $servers + ',' + ($Global:ConfigScheduleUpdate['ServerListVariable'].split("`n") -join ',')
                $servers += $Global:ConfigScheduleUpdate['ServerListVariable'].split("`n")
             }
         } #>
         Write-Output "VMs: $($servers)"
      
   #======== Dynamic serverlist ============
        $scope = $s.Scope
        if($scope -ne $null -and $s.Tags -ne $null){
            $TagsConfig = @{}
            $s.Tags.psobject.properties | ForEach-Object { 
                $TagsConfig[$_.Name] = $_.Value 
            }
        }else{
            $TagsConfig = $null
        }
        if($s.TagOperators -ne $null -and ($s.TagOperators -eq 0 -or $s.TagOperators -eq 1)){
            $TagOperators = $s.TagOperators
        }else{
            $TagOperators = 0  ###### Default value is 0
        }
        Write-Output "AzureQuery scope: $($Scope); Tags: $($TagsConfig); TagOperators: $($TagOperators)"
     
       $AzureContext = (Connect-AzAccount -Identity -Subscription  $($s.Subscription)).context 
       
	   $VMs = Get-AzVM  #-ResourceGroupName BillingFE # -Name EUINTCPEV2SOP01 #| Format-List -Property ResourceGroupName,Name,Location,Tags 
       #Write-Output "ALL VMS: $VMs"

	   $TagServers=@()

	if ($TagsConfig -ne $null){
		#====match Any tags =====
		 if ($TagOperators -eq 1) {
         foreach ($T in $TagsConfig.keys){
			 Write-Output "Tags in tagconfig: $T"
          foreach ($vm in $VMs) {
			Write-Output "processing VM: $($VM.Name)"
          if ($VM.Tags.Keys -imatch $T) {
          if($TagsConfig[$T] -imatch $vm.Tags[$T]) 
            {$TagServers += $VM.Name}
          }
         }
       }
       Write-Output "VMs in TagsConfig: $($TagServers)"
       }
       else{
     #====match All tags =====
      foreach ($vm in $VMs) {
       $Matchtag= $true
        foreach ($T in $TagsConfig.keys){
           if (($VM.Tags.Keys -imatch $T) -and ($TagsConfig[$T] -imatch $vm.Tags[$T])){}
           else { $Matchtag= $false} 
           }
        if ($Matchtag) {$TagServers+=$VM.name}
         }
      Write-Output "VMs in TagsConfig: $($TagServers)"
      }
     }
	}
   #$Global:Serverlist = ($servers -join ',')
   $Global:Serverlist = $servers + $TagServers
   if (!(Test-Path $Root)) 
   {
	   throw "The $($root) path doesn't exist, pls check onboarding process"
   }

   if (!(Test-Path "$($Root)\Serverlist")) {New-Item -path "$($Root)\Serverlist" -ItemType directory}
   if (($Global:Serverlist).Count -eq 0) {throw "server list is null, please check"}
   
   ($Global:Serverlist -join "`r`n") | Out-File -FilePath "$($Root)\Serverlist\$($SLName).txt" -Force -ErrorAction Stop

   Write-Output "The server list is generated to $($Root)\Serverlist\$($SLName).txt"
   $AzAutomationVariable= Get-AzAutomationVariable -AutomationAccountName $($s.AutomationAccountName) -Name $SLName -ResourceGroupName $($s.ResourceGroupName) -ErrorAction SilentlyContinue
   if($AzAutomationVariable -eq $null) {  
    New-AzAutomationVariable -AutomationAccountName $($s.AutomationAccountName) -Name $SLName -Encrypted $False -Value ($Global:Serverlist -join "`n") -ResourceGroupName $($s.ResourceGroupName) -DefaultProfile $AzureContext -ErrorAction Stop
    }
   else {
    Set-AzAutomationVariable -AutomationAccountName $($s.AutomationAccountName) -Name $SLName  -Encrypted $False -Value ($Global:Serverlist -join "`n") -ResourceGroupName $($s.ResourceGroupName) -DefaultProfile $AzureContext -ErrorAction Stop
    }
}
catch
{
    Write-Error "Exception while executing the main script : $($_.Exception)" 
    throw "Exception: $_"
}
finally
{
    if($Global:ConfigScheduleUpdate.RunOnAzure -eq 0){
        popd
    }
}