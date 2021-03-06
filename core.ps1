#using module .\Include.psm1

param(
    [Parameter(Mandatory = $false)]
    [Array]$Algorithm = $null,

    [Parameter(Mandatory = $false)]
    [Array]$PoolsName = $null,

    [Parameter(Mandatory = $false)]
    [array]$CoinsName= $null,

    [Parameter(Mandatory = $false)]
    [String]$MiningMode = $null,

    [Parameter(Mandatory = $false)]
    [array]$Groupnames = $null,

    [Parameter(Mandatory = $false)]
    [string]$PercentToSwitch = $null


)



. .\Include.ps1

##Parameters for testing, must be commented on real use


#$MiningMode='Automatic'
#$MiningMode='Manual'

#$PoolsName=('ahashpool','mining_pool_hub','hash_refinery')
#$PoolsName='whattomine_virtual'
#$PoolsName='yiimp'
#$PoolsName='ahashpool'
#$PoolsName=('hash_refinery','zpool')
#$PoolsName='mining_pool_hub'
#$PoolsName='zpool'
#$PoolsName='hash_refinery'
#$PoolsName='suprnova'

#$PoolsName="Nicehash"

#$Coinsname =('bitcore','Signatum','Zcash')
#$Coinsname ='zcash'
#$Algorithm =('equihash')

#$Groupnames=('rx580')



$ErrorActionPreference = "Continue"
if ($Groupnames -eq $null) {$Host.UI.RawUI.WindowTitle = "MegaMiner"} else {$Host.UI.RawUI.WindowTitle = "MM-" + ($Groupnames -join "/")}
$env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID' #This align cuda id with nvidia-smi order

$progressPreference = 'silentlyContinue' #No progress message on web requests

Set-Location (Split-Path $script:MyInvocation.MyCommand.Path)

Get-ChildItem . -Recurse | Unblock-File
try {if ((Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)) {Start-Process powershell -Verb runAs -ArgumentList "Add-MpPreference -ExclusionPath '$(Convert-Path .)'"}}catch {}




#Start log file
    Clear_log
    $LogFile=".\Logs\$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"
    Start-Transcript $LogFile #for start log msg
    Stop-Transcript
    $Types=Get_Mining_Types -filter $Groupnames
    writelog ( get_gpu_information $Types |ConvertTo-Json) $logfile $false
    

 
    


$ActiveMiners = @()
$ActiveMinersIdCounter=0
$Activeminers=@()
$ShowBestMinersOnly=$true
$FirstTotalExecution =$true
$StartTime=get-date




$Screen = get_config_variable "STARTSCREEN"
  


#---Paraneters checking

if ($MiningMode -ne 'Automatic' -and $MiningMode -ne 'Manual' -and $MiningMode -ne 'Automatic24h'){
    "Parameter MiningMode not valid, valid options: Manual, Automatic, Automatic24h" |Out-host
    EXIT
   }


   
$PoolsChecking=Get_Pools -Querymode "info" -PoolsFilterList $PoolsName -CoinFilterList $CoinsName -Location $location -AlgoFilterList $Algorithm   

$PoolsErrors=@()
switch ($MiningMode){
    "Automatic"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnAutomaticMode -eq $false}
    "Automatic24h"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnAutomatic24hMode -eq $false}
    "Manual"{$PoolsErrors =$PoolsChecking |Where-Object ActiveOnManualMode -eq $false }
    }


$PoolsErrors |ForEach-Object {
    "Selected MiningMode is not valid for pool "+$_.name |Out-host
    EXIT
}



if ($MiningMode -eq 'Manual' -and ($Coinsname | Measure-Object).count -gt 1){
    "On manual mode only one coin must be selected" |Out-host
    EXIT
   }


if ($MiningMode -eq 'Manual' -and ($Coinsname | Measure-Object).count -eq 0){
    "On manual mode must select one coin" |Out-host
    EXIT
   }   
 
if ($MiningMode -eq 'Manual' -and ($Algorithm | measure-object).count -gt 1){
    "On manual mode only one algorithm must be selected" |Out-host
    EXIT
   }
    

#parameters backup

    $ParamAlgorithmBCK=$Algorithm
    $ParamPoolsNameBCK=$PoolsName
    $ParamCoinsNameBCK=$CoinsName
    $ParamMiningModeBCK=$MiningMode


    
set_WindowSize 165 60 
    
$IntervalStartAt = (Get-Date) #first inicialization, must be outside loop


ErrorsToLog $LogFile


$Msg="Starting Parameters: "   
$Msg+=" //Algorithm: "+[String]($Algorithm -join ",") 
$Msg+=" //PoolsName: "+[String]($PoolsName -join ",") 
$Msg+=" //CoinsName: "+[String]($CoinsName -join ",") 
$Msg+=" //MiningMode: "+$MiningMode
$Msg+=" //Groupnames: "+[String]($Groupnames -join ",") 
$Msg+=" //PercentToSwitch: "+$PercentToSwitch

WriteLog $msg $LogFile $False

 


#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#This loop will be runnig forever
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------------


while ($true) {

    Clear-Host;$repaintScreen=$true

    WriteLog "New interval starting............." $LogFile $True
    Writelog ( Get_ComputerStats |ConvertTo-Json) $logfile $false

    $Location=get_config_variable "LOCATION"


    if ($PercentToSwitch -eq "") {$PercentToSwitch2 = [int](get_config_variable "PERCENTTOSWITCH")} else {$PercentToSwitch2=[int]$PercentToSwitch}
    $DelayCloseMiners=get_config_variable "DELAYCLOSEMINERS"
    
    $Types=Get_Mining_Types -filter $Groupnames
    
    $NumberTypesGroups=($Types | Measure-Object).count
    if ($NumberTypesGroups -gt 0) {$InitialProfitsScreenLimit=[Math]::Floor( 25 /$NumberTypesGroups)} #screen adjust to number of groups
    if ($FirstTotalExecution) {$ProfitsScreenLimit=$InitialProfitsScreenLimit}
                         

    $Currency= get_config_variable "CURRENCY"
    $BechmarkintervalTime=[int](get_config_variable "BENCHMARKTIME" )
    $LocalCurrency= get_config_variable "LOCALCURRENCY"
    if ($LocalCurrency.length -eq 0) { #for old config.txt compatibility
        switch ($location) {
            'Europe' {$LocalCurrency="EURO"}
            'US'     {$LocalCurrency="DOLLAR"}
            'ASIA'   {$LocalCurrency="DOLLAR"}
            'GB'     {$LocalCurrency="GBP"}
            default {$LocalCurrency="DOLLAR"}
            }
        }
    

    #Donation
    $LastIntervalTime= (get-date) - $IntervalStartAt
    $IntervalStartAt = (Get-Date)
    $DonationPastTime= ((Get-Content Donation.ctr) -split '_')[0]
    $DonatedTime = ((Get-Content Donation.ctr) -split '_')[1]

    If ($DonationPastTime -eq $null -or $DonationPastTime -eq "" ) {$DonationPastTime=0}
    If ($DonatedTime -eq $null -or $DonatedTime -eq "" ) {$DonatedTime=0}

    $ElapsedDonationTime = [int]($DonationPastTime) + $LastIntervalTime.minutes + ($LastIntervalTime.hours *60)
    $ElapsedDonatedTime = [int]($DonatedTime) + $LastIntervalTime.minutes + ($LastIntervalTime.hours *60)

    
    $ConfigDonateTime= [int](get_config_variable "DONATE")
    

    #if ($DonateTime -gt 5) {[int]$DonateTime=5}
    
    #Activate or deactivate donation
    if ($ElapsedDonationTime -gt 1440 -and $ConfigDonateTime -gt 0) { # donation interval

                $DonationInterval = $true
                $UserName = "tutulino"
                #$WorkerName = "Megaminer"
                $CoinsWallets=@{} 
                $CoinsWallets.add("BTC","1AVMHnFgc6SW33cwqrDyy2Fug9CsS8u6TM")

                $NextInterval= ($ConfigDonateTime *60) - ($ElapsedDonatedTime *60)

                $Algorithm=$null
                $PoolsName="DonationPool"
                $CoinsName=$null
                $MiningMode="Automatic"

                if ($ElapsedDonatedTime -ge $ConfigDonateTime) {"0_0" | Set-Content  -Path Donation.ctr} else {[string]$DonationPastTime+"_"+[string]$ElapsedDonatedTime | Set-Content  -Path Donation.ctr}

                WriteLog ("Next interval you will be donating , thanks for your support") $LogFile $True

            }
            else { #NOT donation interval
                    $DonationInterval = $false
                    $NextInterval=get_config_variable "INTERVAL"

                    $Algorithm=$ParamAlgorithmBCK
                    $PoolsName=$ParamPoolsNameBCK
                    $CoinsName=$ParamCoinsNameBCK
                    $MiningMode=$ParamMiningModeBCK
                    $UserName= get_config_variable "USERNAME"
                    $WorkerName= get_config_variable "WORKERNAME"
                    $CoinsWallets=@{} 
                    ((Get-Content config.txt | Where-Object {$_ -like '@@WALLET_*=*'}) -replace '@@WALLET_*=*','').TrimEnd() | ForEach-Object {$CoinsWallets.add(($_ -split "=")[0],($_ -split "=")[1])}
                
                    [string]$ElapsedDonationTime+"_0" | Set-Content  -Path Donation.ctr

                 }
        

    $Rates = [pscustomObject]@{}
    try { $Currency | ForEach-Object {$Rates | Add-Member $_ (Invoke-WebRequest "https://api.cryptonator.com/api/ticker/btc-$_" -UseBasicParsing | ConvertFrom-Json).ticker.price}} catch {}

    ErrorsToLog $LogFile


    WriteLog "Loading Pools Information............." $LogFile $True

    #Load information about the Pools, only must read parameter passed files (not all as mph do), level is Pool-Algo-Coin
     do
        {
        $Pools=Get_Pools -Querymode "core" -PoolsFilterList $PoolsName -CoinFilterList $CoinsName -Location $Location -AlgoFilterList $Algorithm
        if  ($Pools.Count -eq 0) {
                $Msg="NO POOLS!....retry in 10 sec --- REMEMBER, IF YOUR ARE MINING ON ANONYMOUS WITHOUT AUTOEXCHANGE POOLS LIKE YIIMP, NANOPOOL, ETC. YOU MUST SET WALLET FOR AT LEAST ONE POOL COIN IN CONFIG.TXT"
                WriteLog $msg $logFile $true
                
                Start-Sleep 10}
        }
    while ($Pools.Count -eq 0) 
    
    $Pools | Select-Object name -unique | foreach-object {Writelog ("Pool "+$_.name+" was responsive....") $logfile $true}

    #Load information about the Miner asociated to each Coin-Algo-Miner

    $Miners= @()

    foreach ($MinerFile in (Get-ChildItem "Miners" | Where-Object extension -eq '.json'))  
        {
            try { $Miner =$MinerFile | Get-Content | ConvertFrom-Json } 
            catch 
                {  Writelog "-------BAD FORMED JSON: $MinerFile" $LogFile $true
                Exit}
 
   
                    foreach ($Algo in ($Miner.Algorithms))
                        {
                            $HashrateValue= 0
                            $HashrateValueDual=0
                            $Hrs=$null

                            ##Algoname contains real name for dual and no dual miners
                            $AlgoName =  (($Algo.PSObject.Properties.Name -split ("_"))[0]).toupper().trimend()
                            $AlgoNameDual = (($Algo.PSObject.Properties.Name -split ("_"))[1])
                            if ($AlgoNameDual -ne $null) {$AlgoNameDual=$AlgoNameDual.toupper()}
                            $AlgoLabel = ($Algo.PSObject.Properties.Name -split ("_"))[2]
                            if ($AlgoNameDual -eq $null) {$Algorithms=$AlgoName} else {$Algorithms=$AlgoName+"_"+$AlgoNameDual}
                          

                            $PowerLimits=get_config_variable "AUTOPOWERLIMIT" | ConvertFrom-Json
                            if ($PowerLimits -eq $null) {$PowerLimits=0} #need at least one element for loop
                            
                            
                                    
                            ForEach ( $TypeGroup in $types) {#generate pools for each gpu group

                               Foreach ($PowerLimit in $PowerLimits) {    
                                    
                                    if  ((Compare-object $TypeGroup.type $Miner.Types -IncludeEqual -ExcludeDifferent | Measure-Object).count -gt 0) { #check group and miner types are the same
                                        $Pools | where-object Algorithm -eq $AlgoName | ForEach-Object {   #Search pools for that algo
                                            
                                                if ((($Pools | Where-Object Algorithm -eq $AlgoNameDual) -ne  $null) -or ($Miner.Dualmining -eq $false)){
                                                $DualMiningMainCoin=$Miner.DualMiningMainCoin -replace $null,""
                                                if (((Compare-object $_.info $DualMiningMainCoin -IncludeEqual -ExcludeDifferent | Measure-Object).count -gt 0) -or $Miner.Dualmining -eq $false) {  #not allow dualmining if main coin not coincide


                                                    $Hrs = Get_Hashrates -minername $Minerfile.basename -algorithm $Algorithms -GroupName $TypeGroup.GroupName -AlgoLabel  $AlgoLabel -PowerLimit $PowerLimit | Where-Object TimeRunning -gt 100 

                                                    $HashrateValue=($Hrs | measure-object -property Speed -average).average
                                                    $HashrateValueDual=($Hrs | measure-object -property SpeedDual -average).average
                                                    $PowerValue=($Hrs | measure-object -property Power -average).average
                                            
                                                    $ElectricityCostValue= ((get_config_variable "ElectricityCost" |ConvertFrom-Json) |where-object  HourStart -le (get-date).Hour |where-object  HourEnd -ge (get-date).Hour).CostKwhBTC


                                                    if (($Types | Measure-Object).Count -gt 1) {
                                                                if ($_.name -eq 'Nicehash') {$WorkerName2=$WorkerName+$TypeGroup.GroupName} else {$WorkerName2=$WorkerName+'_'+$TypeGroup.GroupName}
                                                            }
                                                            else  {$WorkerName2=$WorkerName} 


                                                    $Arguments = $Miner.Arguments  -replace '#PORT#',$_.Port -replace '#SERVER#',$_.Host -replace '#PROTOCOL#',$_.Protocol -replace '#LOGIN#',$_.user -replace '#PASSWORD#',$_.Pass -replace "#GpuPlatform#",$TypeGroup.GpuPlatform  -replace '#ALGORITHM#',$Algoname -replace '#ALGORITHMPARAMETERS#',$Algo.PSObject.Properties.Value -replace '#WORKERNAME#',$WorkerName2  -replace '#DEVICES#',$TypeGroup.Gpus   -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#ETHSTMODE#",$_.EthStMode -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode                   
                                                    if ($Miner.PatternConfigFile -ne $null) {
                                                                    $ConfigFileArguments =  replace_foreach_gpu (get-content $Miner.PatternConfigFile -raw)  $TypeGroup.Gpus
                                                                    $ConfigFileArguments = $ConfigFileArguments -replace '#PORT#',$_.Port -replace '#SERVER#',$_.Host -replace '#PROTOCOL#',$_.Protocol -replace '#LOGIN#',$_.user -replace '#PASSWORD#',$_.Pass -replace "#GpuPlatform#",$TypeGroup.GpuPlatform   -replace '#ALGORITHM#',$Algoname -replace '#ALGORITHMPARAMETERS#',$Algo.PSObject.Properties.Value -replace '#WORKERNAME#',$WorkerName2  -replace '#DEVICES#',$TypeGroup.Gpus -replace '#DEVICESCLAYMODE#',$TypeGroup.GpusClayMode  -replace '#DEVICESETHMODE#',$TypeGroup.GpusETHMode -replace '#GROUPNAME#',$TypeGroup.Groupname -replace "#ETHSTMODE#",$_.EthStMode -replace "#DEVICESNSGMODE#",$TypeGroup.GpusNsgMode                   
                                                                }

                                                                
                                                        if ($MiningMode -eq 'Automatic24h') {
                                                                $MinerRevenue=[Double]([double]$HashrateValue * [double]$_.Price24h)
                                                            
                                                                }
                                                            else {
                                                                $MinerRevenue=[Double]([double]$HashrateValue * [double]$_.Price)}

                                                        #apply fee to revenue 
                                                        if ([double]$Miner.Fee -gt 0) {$MinerRevenue=$MinerRevenue -($MinerRevenue*[double]$Miner.fee)} #MinerFee
                                                        if ([double]$_.Fee -gt 0) {$MinerRevenue=$MinerRevenue -($MinerRevenue*[double]$_.fee)} #PoolFee

                                                        $PoolAbbName=$_.Abbname

                                                        $PoolPass=$_.Pass -replace '#WORKERNAME#',$WorkerName2
                                                        $PoolUser=$_.User -replace '#WORKERNAME#',$WorkerName2

                                                        if ($_.PoolWorkers -eq $null) {$PoolWorkers=""} else {$PoolWorkers=$_.Poolworkers.tostring()}
                                                        $MinerRevenueDual = $null
                                                        $PoolDual = $null
                                                        

                                                        if ($Miner.Dualmining) 
                                                            {
                                                            if ($MiningMode -eq 'Automatic24h')   {
                                                                $PoolDual = $Pools |where-object Algorithm -eq $AlgoNameDual | sort-object price24h -Descending| Select-Object -First 1
                                                                $MinerRevenueDual = [Double]([double]$HashrateValueDual * [double]$PoolDual.Price24h)
                                                                }   

                                                                else {
                                                                        $PoolDual = $Pools |where-object Algorithm -eq $AlgoNameDual | sort-object price -Descending| Select-Object -First 1
                                                                        $MinerRevenueDual = [Double]([double]$HashrateValueDual * [double]$PoolDual.Price)
                                                                        }

                                                            #apply fee to profit       
                                                            if ($Miner.Fee -gt 0) {$MinerRevenueDual=$MinerRevenueDual -($MinerRevenueDual*[double]$Miner.fee)}             
                                                            if ($PoolDual.Fee -gt 0) {$MinerRevenueDual=$MinerRevenueDual -($MinerRevenueDual*[double]$PoolDual.fee)}       
                                                            
                                                            $WorkerName3=$WorkerName2+'D'
                                                            $PoolPassDual=$PoolDual.Pass -replace '#WORKERNAME#',$WorkerName3
                                                            $PoolUserDual=$PoolDual.user -replace '#WORKERNAME#',$WorkerName3

                                                            $Arguments = $Arguments -replace '#PORTDUAL#',$PoolDual.Port -replace '#SERVERDUAL#',$PoolDual.Host  -replace '#PROTOCOLDUAL#',$PoolDual.Protocol -replace '#LOGINDUAL#',$PoolUserDual -replace '#PASSWORDDUAL#',$PoolPassDual  -replace '#ALGORITHMDUAL#',$AlgonameDual -replace '#WORKERNAME#',$WorkerName3 
                                                            if ($Miner.PatternConfigFile -ne $null) {
                                                                                $ConfigFileArguments = $ConfigFileArguments -replace '#PORTDUAL#',$PoolDual.Port -replace '#SERVERDUAL#',$PoolDual.Host  -replace '#PROTOCOLDUAL#',$PoolDual.Protocol -replace '#LOGINDUAL#',$PoolUserDual -replace '#PASSWORDDUAL#',$PoolPassDual -replace '#ALGORITHMDUAL#' -replace '#WORKERNAME#',$WorkerName3 
                                                                                }

                                                            $PoolAbbName += '|' + $PoolDual.Abbname

                                                            if ($PoolDual.Poolworkers -ne $null) {$PoolWorkers += '|' + $PoolDual.Poolworkers.tostring()}

                                                            $AlgoNameDual=$AlgoNameDual.toupper()
                                                            $PoolDual.Info=$PoolDual.Info.tolower()
                                                            }
                                                        
                                                        
                                                        

                                                        $Miners += [pscustomobject] @{  
            
                                                                            AlgoLabel=$AlgoLabel
                                                                            Algorithm = $AlgoName
                                                                            AlgorithmDual = $AlgoNameDual
                                                                            Algorithms=$Algorithms
                                                                            API = $Miner.API
                                                                            Arguments=$Arguments
                                                                            Coin = $_.Info.tolower()
                                                                            CoinDual = $PoolDual.Info
                                                                            ConfigFileArguments = $ConfigFileArguments
                                                                            DualMining = $Miner.Dualmining
                                                                            ExtractionPath = $Miner.ExtractionPath
                                                                            GenerateConfigFile = $miner.GenerateConfigFile -replace '#GROUPNAME#',$TypeGroup.Groupname
                                                                            GroupId = $TypeGroup.Id
                                                                            GroupName = $TypeGroup.GroupName
                                                                            GroupType = $TypeGroup.Type
                                                                            GroupDevices = $TypeGroup.gpus
                                                                            HashRate = $HashRateValue
                                                                            Hashrates   = if ($Miner.Dualmining) {(ConvertTo_Hash ($HashRateValue)) + "/s|"+(ConvertTo_Hash $HashrateValueDual) + "/s"} else {(ConvertTo_Hash $HashRateValue) +"/s"}
                                                                            HashRateDual = $HashrateValueDual
                                                                            Host =$_.Host
                                                                            Location = $_.location
                                                                            MinerFee= if ($Miner.Fee -eq $null) {$null} else {[double]$Miner.fee}
                                                                            Name = $Minerfile.basename
                                                                            Path = $Miner.Path
                                                                            PoolAbbName = $PoolAbbName
                                                                            PoolFee = if ($_.Fee -eq $null) {$null} else {[double]$_.fee}
                                                                            PoolName = $_.name
                                                                            PoolNameDual = $PoolDual.name
                                                                            PoolPass= $PoolPass
                                                                            PoolPrice=if ($MiningMode -eq 'Automatic24h') {[double]$_.Price24h} else {[double]$_.Price}
                                                                            PoolPriceDual=if ($MiningMode -eq 'Automatic24h') {[double]$PoolDual.Price24h} else {[double]$PoolDual.Price}
                                                                            PoolWorkers = $PoolWorkers
                                                                            Port = if ((get_config_variable "GPUGROUPS") -eq "") {$miner.ApiPort} else {$null}
                                                                            PowerAvg = $PowerValue
                                                                            PowerLimit=[int]$PowerLimit
                                                                            PrelaunchCommand = $Miner.PrelaunchCommand
                                                                            Profits=$MinerRevenue + $MinerRevenueDual - ($ElectricityCostValue*($PowerValue*24)/1000) #Profit is revenue less electricity cost, can separate profit in dual and non dual because electricity cost can be divided
                                                                            Revenue=$MinerRevenue
                                                                            RevenueDual=$MinerRevenueDual
                                                                            SpeedReads=$Hrs
                                                                            Symbol = $_.Symbol
                                                                            SymbolDual = $PoolDual.Symbol
                                                                            URI = $Miner.URI
                                                                            Username = $PoolUser
                                                                            UsernameDual = $PoolUserDual
                                                                            UsernameReal = ($PoolUser -split '\.')[0]
                                                                            UsernameRealDual = ($PoolUserDual -split '\.')[0]
                                                                            WalletMode=$_.WalletMode
                                                                            WalletSymbol = $_.WalletSymbol
                                                                            Workername= $WorkerName2
                                                                            WorkernameDual= $WorkerName3
                                                                            Wrap =$Miner.Wrap

                                                                        }
                                    
                                                    }                       
                                                }          
            
                                    }  #end foreach pool
                                } #  end if types 
                               
                            } #end power limits

                        } # end Types loop 

                    }
               # }            
        }
             

    Writelog ("Miners detected: "+ [string]($Miners.count)+".........") $LogFile $true    
     
    #Launch download of miners    
    $Miners | where-object {$_.URI -ne $null -and $_.ExtractionPath -ne $null -and $_.Path -ne $null -and $_.URI -ne "" -and $_.ExtractionPath -ne "" -and $_.Path -ne ""} | Select-Object URI, ExtractionPath,Path -Unique | ForEach-Object {
                Start_Downloader -URI $_.URI  -ExtractionPath $_.ExtractionPath -Path $_.Path
            }
    
    ErrorsToLog $LogFile
    
    #Paint no miners message
    $Miners = $Miners | Where-Object {Test-Path $_.Path}
    if ($Miners.Count -eq 0) {Writelog "NO MINERS!" $LogFile $true ; EXIT}


    #Update the active miners list which is alive for  all execution time
    $ActiveMiners | ForEach-Object {
                    #Search miner to update data
                
                     $Miner = $miners | Where-Object Name -eq $_.Name | 
                            Where-Object Coin -eq $_.Coin | 
                            Where-Object Algorithm -eq $_.Algorithm | 
                            Where-Object CoinDual -eq $_.CoinDual | 
                            Where-Object AlgorithmDual -eq $_.AlgorithmDual | 
                            Where-Object PoolAbbName -eq $_.PoolAbbName |
                            Where-Object Location -eq $_.Location |
                            Where-Object GroupId -eq $_.GroupId |
                            Where-Object AlgoLabel -eq $_.AlgoLabel |
                            Where-Object PowerLimit -eq $_.PowerLimit
                            
                    $_.Best = $false
                    $_.NeedBenchmark = $false
                    $_.ConsecutiveZeroSpeed=0
                    if ($_.BenchmarkedTimes -ge 2 -and $_.AnyNonZeroSpeed -eq $false) {$_.Status='Cancelled'}
                    $_.AnyNonZeroSpeed  = $false

                    

                    $TimeActive=($_.ActiveTime.Hours*3600)+($_.ActiveTime.Minutes*60)+$_.ActiveTime.Seconds
                    if (($_.FailedTimes -gt 3) -and ($TimeActive -lt 180) -and (($ActiveMiners | Measure-Object).count -gt 1)){$_.Status='Cancelled'} #Mark as cancelled if more than 3 fails and running less than 180 secs, if no other alternative option, try forerever

                   
                    if (($Miner | Measure-Object).count -gt 1) {
                            Clear-Host;$repaintScreen=$true
                            "DUPLICATED ALGO "+$MINER.ALGORITHM+" ON "+$MINER.NAME | Out-host 
                            EXIT}                 

                    if ($Miner) {
                            $_.GroupId  = $Miner.GroupId
                            $_.Profits = $Miner.Profits
                            $_.RevenueDual = $Miner.RevenueDual
                            $_.Revenue = $Miner.Revenue
                            $_.PoolPrice = $Miner.PoolPrice
                            $_.PoolPriceDual = $Miner.PoolPriceDual
                            $_.HashRate  = [double]$Miner.HashRate
                            $_.HashRateDual  = [double]$Miner.HashRateDual
                            $_.SpeedReads = $Miner.SpeedReads
                            $_.PowerAvg = $Miner.PowerAvg
                            $_.Hashrates   = $miner.hashrates
                            $_.PoolWorkers = $Miner.PoolWorkers
                            $_.PoolFee= $Miner.PoolFee
                            $_.IsValid = $true #not remove, necessary if pool fail and is operative again
                            $_.BestBySwitch  = ""
                            $_.Arguments= $miner.Arguments
                            }
                    else {
                            $_.IsValid = $false #simulates a delete
                           
                            }
                
                }


    ##Add new miners to list
    $Miners | ForEach-Object {
                
                    $ActiveMiner = $ActiveMiners | Where-Object Name -eq $_.Name | 
                            Where-Object Coin -eq $_.Coin | 
                            Where-Object Algorithm -eq $_.Algorithm | 
                            Where-Object CoinDual -eq $_.CoinDual | 
                            Where-Object AlgorithmDual -eq $_.AlgorithmDual | 
                            Where-Object PoolAbbName -eq $_.PoolAbbName |
                            Where-Object Location -eq $_.Location |
                            Where-Object GroupId -eq $_.GroupId |
                            Where-Object AlgoLabel -eq $_.AlgoLabel |
                            Where-Object PowerLimit -eq $_.PowerLimit

                
                    if ($ActiveMiner -eq $null) {
                        $ActiveMiners += [pscustomObject]@{
                            ActivatedTimes       = 0
                            ActiveTime           = [TimeSpan]0
                            AlgoLabel            = $_.AlgoLabel
                            Algorithm            = $_.Algorithm
                            AlgorithmDual        = $_.AlgorithmDual
                            Algorithms           = $_.Algorithms
                            AnyNonZeroSpeed      = $false                            
                            API                  = $_.API
                            Arguments            = $_.Arguments
                            BenchmarkedTimes     = 0
                            Best                 = $false
                            BestBySwitch         = ""
                            BestTimes            = 0
                            ConsecutiveZeroSpeed = 0
                            Coin                 = $_.coin
                            CoinDual             = $_.CoinDual
                            ConfigFileArguments  = $_.ConfigFileArguments
                            DualMining           = $_.DualMining
                            FailedTimes          = 0
                            GenerateConfigFile   = $_.GenerateConfigFile
                            GroupDevices         = $_.GroupDevices
                            GroupName            = $_.GroupName
                            GroupId              = $_.GroupId
                            GroupType             = $_.GroupType
                            HashRate             = [double]$_.HashRate
                            HashRateDual         = [double]$_.HashRateDual
                            Hashrates            = $_.hashrates
                            Host                 = $_.Host
                            Id                   = $ActiveMinersIdCounter
                            IsValid              = $true
                            LastTimeActive       = [TimeSpan]0
                            Location             = $_.Location  
                            MinerFee             = $_.MinerFee                                                      
                            Name                 = $_.Name
                            NeedBenchmark        = $false                                                        
                            Path                 = Convert-Path $_.Path
                            PoolAbbName          = $_.PoolAbbName
                            PoolFee              = $_.PoolFee
                            PoolName             = $_.PoolName
                            PoolNameDual         = $_.PoolNameDual
                            PoolPrice            = $_.PoolPrice
                            PoolPriceDual        = $_.PoolPriceDual
                            PoolWorkers          = $_.PoolWorkers
                            PoolHashrate         = $null
                            PoolHashrateDual     = $null
                            PoolPass             = $_.PoolPass
                            Port                 = $_.Port
                            PowerAvg             = $_.PowerAvg
                            PowerLive            = 0
                            PowerLimit           = $_.PowerLimit
                            PrelaunchCommand     = $_.PrelaunchCommand
                            Process              = $null
                            ProfitsLive          = 0
                            Profits              = $_.Profits
                            Revenue              = $_.Revenue
                            RevenueDual          = $_.RevenueDual
                            RevenueLive          = 0
                            RevenueLiveDual      = 0
                            SpeedLive            = 0
                            SpeedLiveDual        = 0
                            SpeedReads           = $_.SpeedReads
                            Status               = ""
                            Symbol               = $_.Symbol
                            SymbolDual           = $_.SymbolDual    
                            TimeRunning          = [TimeSpan]0              
                            Username             = $_.Username
                            UsernameDual         = $_.UsernameDual
                            UserNameReal         = $_.UserNameReal
                            UserNameRealDual     = $_.UserNameRealDual
                            WalletMode           = $_.WalletMode
                            WalletSymbol         = $_.WalletSymbol
                            Workername           = $_.Workername
                            WorkernameDual       = $_.WorkernameDual                            
                            Wrap                 = $_.Wrap

                        }
                        $ActiveMinersIdCounter++
                }
            }



    Writelog ("Active Miners-pools: "+ [string]($ActiveMiners.count)+".........") $LogFile $true                

    ErrorsToLog $LogFile


    #update miners that need benchmarks
                                                
    $ActiveMiners | ForEach-Object {

        if ($_.BenchmarkedTimes -le 2 -and $_.isvalid -and ($_.Hashrate -eq 0 -or ($_.AlgorithmDual -ne $null -and $_.HashrateDual -eq 0)))
            {$_.NeedBenchmark=$true} 
        }



    Writelog ("Active Miners-pools selected for benchmark: "+ [string](($ActiveMiners | where-object NeedBenchmark -eq $true).count)+".........") $LogFile $true                

    #For each type, select most profitable miner, not benchmarked has priority, only new miner is lauched if new profit is greater than old by percenttoswitch
    foreach ($Type in $Types) {

        $BestIdNow=($ActiveMiners |Where-Object {$_.IsValid -and $_.status -ne "Canceled" -and  $_.GroupId -eq $Type.Id} | Sort-Object -Descending {if ($_.NeedBenchmark) {1} else {0}}, {$_.Profits},Algorithm,PowerLimit | Select-Object -First 1 | Select-Object -ExpandProperty  id)
        if ($BestIdNow -ne $null) {
                    $ProfitNow=$ActiveMiners[$BestIdNow].profits 

                    $ActiveMiners[$BestIdNow].BestTimes++

                    $BestIdLast=($ActiveMiners |Where-Object {$_.IsValid -and $_.status -eq "Running" -and  $_.GroupId -eq $Type.Id} | Select-Object -ExpandProperty  id)

                    Writelog ($ActiveMiners[$BestIdNow].name+"/"+$ActiveMiners[$BestIdNow].Algorithms+"(id "+[string]$BestIdNow+") is the best combination for gpu group "+$Type.groupname+" last was id "+[string]$BestIdLast) $LogFile $true                
                    
                    if ($BestIdLast -ne $null) {$ProfitLast=$ActiveMiners[$BestIdLast].profits} else {$ProfitLast=0}
 
                    if ($ProfitNow -gt ($ProfitLast *(1+($PercentToSwitch2/100))) -or $ActiveMiners[$BestIdNow].NeedBenchmark -or $BestIdLast -eq $null) {
                            $ActiveMiners[$BestIdNow].best=$true
                            } 
                        else {
                            $ActiveMiners[$BestIdLast].best=$true 
                            if ($Profitlast -lt $ProfitNow) {
                                    $ActiveMiners[$BestIdLast].BestBySwitch  = "*"
                                    Writelog ($ActiveMiners[$BestIdLast].name+"/"+$ActiveMiners[$BestIdLast].Algorithms+"(id "+[string]$BestIdLast+") continue mining due to @@percenttoswitch value "+$Type.name) $LogFile $true                
                                }
                            }
        
                    }
        }


    ErrorsToLog $LogFile
   
   
      #############################################################

        #Stop miners running if they arent best now 


        $ActiveMiners | Where-Object {$_.Best -eq $false -and $_.Process -ne $null} | ForEach-Object {
                
                    Kill_ProcessId $_.Process.Id
                    $_.process=$null
                    $_.Status = "Idle"
                    WriteLog ("Killing "+$_.name+"/"+$_.Algorithms+"(id "+[string]$_.Id+")") $LogFile
                }
            
        

    #############################################################
    #Start all Miners marked as Best (if they are running does nothing)
    $ActiveMiners | Where-Object Best -eq $true | ForEach-Object {
        
                if ($_.NeedBenchmark) {$NextInterval=$BechmarkintervalTime;$DelayCloseMiners=0} #if one need benchmark next interval will be short and fast change

                #Launch
                if ($_.Process -eq $null -or $_.Process.HasExited -ne $false) {


                    $_.Status = "Running"
                    
                    
                    #assign a free random api  (not if it is forced in miner file or calculated before)
                    if ($_.Port -eq $null) { $_.Port = get_next_free_port (Get-Random -minimum 2000 -maximum 48000)} 

                    $_.Arguments = $_.Arguments -replace '#APIPORT#',$_.Port
                    
                    $_.ConfigFileArguments = $_.ConfigFileArguments -replace '#APIPORT#',$_.Port

                    $_.ActivatedTimes++

                    if ($_.GenerateConfigFile -ne "") {$_.ConfigFileArguments | Set-Content ($_.GenerateConfigFile)}

                    #run prelaunch command
                    if ($_.PrelaunchCommand -ne $null -and $_.PrelaunchCommand -ne "") {Start-Process -FilePath $_.PrelaunchCommand}

                    if ($_.GroupType='NVIDIA' -and $_.PowerLimit -gt 0) {set_Nvidia_Powerlimit $_.PowerLimit $_.GroupDevices}
                    if ($_.GroupType='AMD'-and $_.PowerLimit -gt 0){}



                    if ($_.Wrap) {$_.Process = Start-Process -FilePath "PowerShell" -ArgumentList "-executionpolicy bypass -command . '$(Convert-Path ".\Wrapper.ps1")' -ControllerProcessID $PID -Id '$($_.Port)' -FilePath '$($_.Path)' -ArgumentList '$($_.Arguments)' -WorkingDirectory '$(Split-Path $_.Path)'" -PassThru}
                    else {$_.Process = Start_SubProcess -FilePath $_.Path -ArgumentList $_.Arguments -WorkingDirectory (Split-Path $_.Path)}
                
                    start-sleep 1

                    if ($_.Process -eq $null) {
                            $_.Status = "Failed"
                            $_.FailedTimes++
                            Writelog ("Failed start of "+$_.Name+"/"+$_.Algorithms+"("+$_.Id+") --> "+$_.Path+" "+$_.Arguments) $LogFile $false
                        } 
                    else {
                        $_.Status = "Running"
                        $_.LastTimeActive = get-date
                        $_.TimeRunning = [TimeSpan]0
                        Writelog ("Started Process "+[string]$_.Process.Id+" for "+$_.Name+"/"+$_.Algorithms+"("+$_.Id+") --> "+$_.Path+" "+$_.Arguments) $LogFile $false
                        }

                    }
            
                } #end stating miners


      

         #Call api to local currency conversion
        try {
                $CDKResponse = Invoke-WebRequest "https://api.coindesk.com/v1/bpi/currentprice.json" -UseBasicParsing -TimeoutSec 2 | ConvertFrom-Json | Select-Object -ExpandProperty BPI
                Clear-Host;$repaintScreen=$true
            } 
                
            catch {
                Clear-Host;$repaintScreen=$true
                writelog "COINDESK API NOT RESPONDING, NOT POSSIBLE LOCAL COIN CONVERSION" $logfile $true
                }
                
                switch ($LocalCurrency) {
                    'EURO' {$LocalSymbol=[convert]::ToChar(8364) ; $localBTCvalue = [double]$CDKResponse.eur.rate}
                    'DOLLAR'     {$LocalSymbol=+[convert]::ToChar(36)  ; $localBTCvalue = [double]$CDKResponse.usd.rate}
                    'GBP'     {$LocalSymbol=[convert]::ToChar(163)  ; $localBTCvalue = [double]$CDKResponse.gbp.rate}
                    default {$LocalSymbol=" $" ; $localBTCvalue = [double]$CDKResponse.usd.rate}

                }





    $FirstLoopExecution=$True   
    $LoopStarttime=Get-Date
 

    ErrorsToLog $LogFile
    $SwitchLoop = 0

    while ($Host.UI.RawUI.KeyAvailable)  {$host.ui.RawUi.Flushinputbuffer()} #keyb buffer flush



    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------
    #---------------------------------------------------------------------------

    #loop to update info and check if miner is running, exit loop is forced inside                        
    While (1 -eq 1) 
        {

        

        if  ($SwitchLoop -gt 10) {$SwitchLoop=0} #reduces 10-1 ratio of execution 
        $SwitchLoop++ 
        

        $ExitLoop = $false
        

        $LoopTime=(get-date) - $LoopStarttime
        $LoopSeconds=$LoopTime.seconds + $LoopTime.minutes * 60 +  $LoopTime.hours *3600


        $cards=get_gpu_information $Types

      



           #############################################################

         

                   
            #Check Live Speed and record benchmark if necessary
            $ActiveMiners | Where-Object Best -eq $true | ForEach-Object {
                if ($FirstLoopExecution -and $_.NeedBenchmark) {$_.BenchmarkedTimes++}
                $_.SpeedLive = 0
                $_.SpeedLiveDual = 0
                $_.ProfitsLive = 0
                $_.RevenueLive = 0
                $_.RevenueLiveDual = 0
                $Miner_HashRates = $null


                if ($_.Process -eq $null -or $_.Process.HasExited) {
                        if ($_.Status -eq "Running") {
                                    $_.Status = "Failed"
                                    $_.FailedTimes++
                                    writelog ("Detected miner closed "+$_.name+"/"+$_.Algorithm+" (id "+$_.Id+") --> "+$_.Arguments) $logfile $false
                                    $ExitLoop = $true
                                    }
                        else
                            { $ExitLoop = $true}         
                        }

                else {
                        $_.ActiveTime += (get-date) - $_.LastTimeActive 
                       

                        $Miner_HashRates = Get_Live_HashRate $_.API $_.Port 

                        if ($Miner_HashRates -ne $null){
                           
                            $_.SpeedLive = [double]($Miner_HashRates[0])
                            $_.SpeedLiveDual = [double]($Miner_HashRates[1])
                           
                            $_.RevenueLive = $_.SpeedLive * $_.PoolPrice 
                            $_.RevenueLiveDual = $_.SpeedLiveDual * $_.PoolPriceDual
                          
                            $_.PowerLive = ($Cards | Where-Object gpugroup -eq $_.GroupName | Measure-Object -property power_draw -sum).sum

                            $_.Profitslive= $_.RevenueLive + $_.RevenueLiveDual - ($ElectricityCostValue*($_.PowerLive*24)/1000)


                            $_.TimeRunning =(get-date) - $_.LastTimeActive 

                            if ($_.SpeedLive -gt 0) {
                                    $_.ConsecutiveZeroSpeed=0
                                    $_.AnyNonZeroSpeed = $true
                                    if ($_.SpeedReads.count -eq 0) {$_.SpeedReads=@()}
                                    
                                    $_.SpeedReads+=[PSCustomObject]@{
                                                                        Speed = $_.SpeedLive 
                                                                        SpeedDual=  $_.SpeedLiveDual
                                                                        Power = $_.PowerLive
                                                                        Date= (get-date).DateTime
                                                                        Benchmarking =$_.NeedBenchmark
                                                                        TimeRunning = $_.TimeRunning.seconds + ($_.TimeRunning.minutes*60) + ($_.TimeRunning.hours*3600)
                                                                    }
                                    if ($_.SpeedReads.count -gt 200) {$_.SpeedReads = $_.SpeedReads[1..($_.SpeedReads.length-1)]} #if array is greateher than  X delete first element    

                                    if ($_.SpeedReads.count -ge 10) {
                                            Set_Hashrates -algorithm $_.Algorithms -minername $_.Name -GroupName $_.GroupName -AlgoLabel $_.AlgoLabel -Powerlimit $_.PowerLimit -value  $_.SpeedReads
                                            #$_.Hashrate=($_.SpeedReads | measure-object -property Speed -average).average
                                            #$_.HashrateDual=($_.SpeedReads | measure-object -property SpeedDual -average).average
                                            }                                                                    
                                } 
                            else 
                                {$_.ConsecutiveZeroSpeed++}
                                }
                            }          

                if ($_.ConsecutiveZeroSpeed -gt 25 -and $_.NeedBenchmark -ne $true ) { #avoid  miner hangs and wait interval ends
                    writelog ($_.name+"/"+$_.Algorithm+" (if"+$_.Id+") had 25 zero hashrates reads, exiting loop") $logfile $false
                    $_.FailedTimes++
                    $_.status="Failed"
                    #$_.Best= $false
                    $ExitLoop='true'
                    }

            }


        #############################################################

        #display interval
            $TimetoNextInterval= NEW-TIMESPAN (Get-Date) ($LoopStarttime.AddSeconds($NextInterval))
            $TimetoNextIntervalSeconds=($TimetoNextInterval.Hours*3600)+($TimetoNextInterval.Minutes*60)+$TimetoNextInterval.Seconds
            if ($TimetoNextIntervalSeconds -lt 0) {$TimetoNextIntervalSeconds = 0}

            set_ConsolePosition ($Host.UI.RawUI.WindowSize.Width-31) 2
            "|  Next Interval:  $TimetoNextIntervalSeconds secs..." | Out-host
            set_ConsolePosition 0 0

        #display header     
        Print_Horizontal_line  "MegaMiner 5.2"  
        Print_Horizontal_line
        "  (E)nd Interval   (P)rofits    (C)urrent    (H)istory    (W)allets    (S)tats" | Out-host
      
        #display donation message
        
            if ($DonationInterval) {" THIS INTERVAL YOU ARE DONATING, YOU CAN INCREASE OR DECREASE DONATION ON CONFIG.TXT, THANK YOU FOR YOUR SUPPORT !!!!"}

        #display current mining info

        Print_Horizontal_line
        


        if ($SwitchLoop=1) { 

                                writelog ($ActiveMiners | Where-Object Status -eq 'Running'| select-object id,process.Id,groupname,name,poolabbname,Algorithm,AlgorithmDual,SpeedLive,ProfitsLive,location,port,arguments |ConvertTo-Json) $logfile $false
                                
                                #To get pool speed
                                        $PoolsSpeed=@()
                                        
                                        
                                        $A=$ActiveMiners | Where-Object Status -eq 'Running'
                                        
                                        $ActiveMiners | Where-Object Status -eq 'Running' |select-object PoolName,UserNameReal,WalletSymbol,coin,Workername -unique | ForEach-Object { 
                                                            $Info=[PSCustomObject]@{
                                                                                User= $_.UsernameReal
                                                                                PoolName=$_.Poolname
                                                                                ApiKey = get_config_variable ("APIKEY_"+$_.PoolName)
                                                                                Symbol = $_.WalletSymbol
                                                                                Coin= $_.coin
                                                                                Workername= $_.Workername
                                                                                }
                                                            $PoolsSpeed+=Get_Pools -Querymode "speed" -PoolsFilterList $_.Poolname -Info $Info
                                                            }

                                        #Dual miners

                                        $ActiveMiners | Where-Object Status -eq 'Running' |Where-object PoolNameDual -ne $null |select-object PoolnameDual,UserNameRealDual,WalletSymbol,coinDual,Workername -unique | ForEach-Object { 
                                                            $Info=[PSCustomObject]@{
                                                                                User= $_.UsernameRealDual
                                                                                PoolName=$_.PoolnameDual
                                                                                ApiKey = get_config_variable ("APIKEY_"+$_.PoolnameDual)
                                                                                Symbol = $_.WalletSymbol
                                                                                Coin= $_.coinDual
                                                                                Workername= $_.WorkernameDual
                                                                                }
                                                            $PoolsSpeed+=Get_Pools -Querymode "speed" -PoolsFilterList $_.PoolnameDual -Info $Info
                                            }      
                                            
                                            
                                        $ActiveMiners | Where-Object Status -eq 'Running' | ForEach-Object { 
                                                        
                                                        $Me=$PoolsSpeed | where-object PoolName -eq $_.Poolname | where-object Workername -eq $_.Workername |select-object HashRate,PoolName,Workername -first 1

                                                        $_.PoolHashrate=$Me.Hashrate
                                                        

                                                        $MeDual=$PoolsSpeed | where-object PoolName -eq $_.PoolnameDual | where-object Workername -eq $_.WorkernameDual |select-object HashRate,PoolName,Workername -first 1

                                                        $_.PoolHashrateDual=$MeDual.Hashrate
                                                        
                                                        
                                                        }


                            }

                                

  $A=$ActiveMiners | Where-Object Status -eq 'Running'
          $ActiveMiners | Where-Object Status -eq 'Running'| Sort-Object GroupId -Descending | Format-Table -Wrap  (
              @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},   
              @{Label = "GroupName"; Expression ={$_.GroupName}}, 
             # @{Label = "PowLmt"; Expression ={if ($_.PowerLimit -gt 0) {$_.PowerLimit}};align='right'}, 

              @{Label = "LocalSpeed"; Expression = {if  ($_.AlgorithmDual -eq $null) {(ConvertTo_Hash  ($_.SpeedLive))+'/s'} else {(ConvertTo_Hash  ($_.SpeedLive))+'/s|'+(ConvertTo_Hash ($_.SpeedLiveDual))+'/s'} }; Align = 'right'},     
              @{Label = "Rev./Day"; Expression = {($_.RevenueLive.tostring("n5"))+'btc'}; Align = 'right'}, 
              @{Label = "Rev./Day"; Expression = {((([double]$_.RevenueLive + [double]$_.RevenueLiveDual) *  [double]$localBTCvalue ).tostring("n2"))+$LocalSymbol}; Align = 'right'}, 
              @{Label = "Profit/Day"; Expression = {(([double]$_.ProfitsLive *  [double]$localBTCvalue ).tostring("n2"))+$LocalSymbol}; Align = 'right'}, 
              @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm+$_.AlgoLabel+$_.BestBySwitch} else  {$_.Algorithm+$_.AlgoLabel+ '|' + $_.AlgorithmDual+$_.BestBySwitch}}},   
              @{Label = "Coin"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Coin} else  {($_.Coin)+ '|' + ($_.CoinDual)}}},   
              @{Label = "Miner"; Expression = {$_.Name}}, 
              @{Label = "Power"; Expression = {[string]$_.PowerLive+'W'};Align = 'right'}, 
              @{Label = "Efficiency"; Expression = {if  ($_.AlgorithmDual -eq $null) {(ConvertTo_Hash  ($_.SpeedLive/$_.PowerLive))+'/W'} else {$null} }; Align = 'right'},     

              
              @{Label = "PoolSpeed"; Expression = {if  ($_.AlgorithmDual -eq $null) {(ConvertTo_Hash  ($_.PoolHashrate))+'/s'} else {(ConvertTo_Hash  ($_.PoolHashrate))+'/s|'+(ConvertTo_Hash ($_.PoolHashrateDual))+'/s'} }; Align = 'right'},     
              @{Label = "Workers"; Expression = {$_.PoolWorkers}; Align = 'right'},
              @{Label = "Loc."; Expression = {$_.Location}},
              @{Label = "Pool"; Expression = {$_.PoolAbbName}}
<#
              @{Label = "BmkT"; Expression = {$_.BenchmarkedTimes}},
              @{Label = "FailT"; Expression = {$_.FailedTimes}},
              @{Label = "Nbmk"; Expression = {$_.NeedBenchmark}},
              @{Label = "CZero"; Expression = {$_.ConsecutiveZeroSpeed}}
              @{Label = "Port"; Expression = {$_.Port}}
 #>             


          ) | Out-Host


          if ($SwitchLoop=1) {}


        $XToWrite=[ref]0
        $YToWrite=[ref]0      
        Get_ConsolePosition ([ref]$XToWrite) ([ref]$YToWrite)  
        $YToWriteMessages=$YToWrite+1
        $YToWriteData=$YToWrite+2
        Remove-Variable XToWrite
        Remove-Variable YToWrite                          


        #############################################################
        Print_Horizontal_line $Screen


        #display profits screen
        if ($Screen -eq "Profits" -and $repaintScreen) {
        
                   set_ConsolePosition ($Host.UI.RawUI.WindowSize.Width-37) $YToWriteMessages
                    
                    
                    "(B)est Miners/All       (T)op "+[string]$InitialProfitsScreenLimit+"/All" | Out-Host

                    
                    set_ConsolePosition 0 $YToWriteData


                    if ($ShowBestMinersOnly) {
                        $ProfitMiners=@()
                        $ActiveMiners | Where-Object IsValid |ForEach-Object {
                            $ExistsBest=$ActiveMiners | Where-Object GroupId -eq $_.GroupId | Where-Object Algorithm -eq $_.Algorithm | Where-Object AlgorithmDual -eq $_.AlgorithmDual | Where-Object IsValid -eq $true | Where-Object Profits -gt $_.Profits
                                           if ($ExistsBest -eq $null -and $_.Profits -eq 0) {$ExistsBest=$ActiveMiners | Where-Object GroupId -eq $_.GroupId | Where-Object Algorithm -eq $_.Algorithm | Where-Object AlgorithmDual -eq $_.AlgorithmDual | Where-Object IsValid -eq $true | Where-Object hashrate -gt $_.hashrate}
                                           if ($ExistsBest -eq $null -or $_.NeedBenchmark -eq $true) {$ProfitMiners += $_}
                                           }
                           }
                    else 
                           {$ProfitMiners=$ActiveMiners}
                    

                    $ProfitMiners2=@()
                    ForEach ( $TypeId in $types.Id) {
                            $inserted=1
                            $ProfitMiners | Where-Object IsValid |Where-Object GroupId -eq $TypeId | Sort-Object -Descending GroupName,NeedBenchmark,Profits | ForEach-Object {
                                if ($inserted -le $ProfitsScreenLimit) {$ProfitMiners2+=$_ ; $inserted++} #this can be done with select-object -first but then memory leak happens, ¿why?
                                    }
                        }

                        

                    #Display profits  information
                    $ProfitMiners2 | Sort-Object @{expression="GroupName";Ascending=$true}, @{expression="NeedBenchmark";Ascending=$true}, @{expression="Profits";Descending=$true} | Format-Table (
                        @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},   
                        @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm+$_.AlgoLabel} else  {$_.Algorithm+$_.AlgoLabel+ '|' + $_.AlgorithmDual}}},   
                        @{Label = "Coin"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Coin} else  {($_.Symbol)+ '|' + ($_.SymbolDual)}}},   
                        @{Label = "Miner"; Expression = {$_.Name}}, 
                       # @{Label = "PowLmt"; Expression ={if ($_.PowerLimit -gt 0) {$_.PowerLimit}};align='right'}, 
                        @{Label = "PowerAvg"; Expression = {if ($_.NeedBenchmark) {"Benchmarking"} else {$_.PowerAvg.tostring("n0")}}; Align = 'right'}, 
                        @{Label = "StatsSpeed"; Expression = {if ($_.NeedBenchmark) {"Benchmarking"} else {$_.Hashrates}}; Align = 'right'}, 
                        @{Label = "Rev./Day"; Expression = {(($_.Revenue+$_.RenevueDual).tostring("n5"))+"btc" } ; Align = 'right'},
                        @{Label = "Rev./Day"; Expression = {((($_.Revenue+$_.RenevueDual) * [double]$localBTCvalue ).tostring("n2"))+$LocalSymbol } ; Align = 'right'},
                        @{Label = "Profit/Day"; Expression = {if ($_.NeedBenchmark) {"Benchmarking"} else {($_.Profits * [double]$localBTCvalue).tostring("n2")+$LocalSymbol}}; Align = 'right'}, 
                        @{Label = "PoolFee"; Expression = {if ($_.PoolFee -ne $null) {"{0:P2}" -f $_.PoolFee}}; Align = 'right'},
                        @{Label = "MinerFee"; Expression = {if ($_.MinerFee -ne $null) {"{0:P2}" -f $_.MinerFee}}; Align = 'right'},
                        @{Label = "Pool"; Expression = {$_.PoolAbbName}},
                        @{Label = "Location"; Expression = {$_.Location}}
                        

                    )  -GroupBy GroupName  |  Out-Host

                       
                    Remove-Variable ProfitMiners
                    Remove-Variable ProfitMiners2
                    
                   
                }
  

                
                          
        if ($Screen -eq "Current") {
                    

                    set_ConsolePosition 0 $YToWriteData

                    # Display devices info
                    print_gpu_information $Cards
                }
                                    
        
        #############################################################        
                    
        if ($Screen -eq "Wallets" -or $FirstTotalExecution -eq $true) {         


                    if ($WalletsUpdate -eq $null) { #wallets only refresh for manual request

                            $WalletsUpdate=get-date

                            $WalletsToCheck=@()
                            
                            $Pools  | where-object WalletMode -eq 'WALLET' | Select-Object PoolName,AbbName,User,WalletMode,WalletSymbol -unique  | ForEach-Object {
                                    $WalletsToCheck += [pscustomObject]@{
                                                PoolName   = $_.PoolName
                                                AbbName = $_.AbbName
                                                WalletMode = $_.WalletMode
                                                User       = ($_.User -split '\.')[0] #to allow payment id after wallet
                                                Coin = $null
                                                Algorithm = $null
                                                OriginalAlgorithm =$null
                                                OriginalCoin = $null
                                                Host = $null
                                                Symbol = $_.WalletSymbol
                                                }
                                }
                            $Pools  | where-object WalletMode -eq 'APIKEY' | Select-Object PoolName,AbbName,info,Algorithm,OriginalAlgorithm,OriginalCoin,Symbol,WalletMode,WalletSymbol  -unique  | ForEach-Object {
                                    

                                    
                                    $ApiKey = get_config_variable ("APIKEY_"+$_.PoolName)
                                
                                    if ($Apikey -ne "") {
                                            $WalletsToCheck += [pscustomObject]@{
                                                        PoolName   = $_.PoolName
                                                        AbbName = $_.AbbName
                                                        WalletMode = $_.WalletMode
                                                        User       = $null
                                                        Coin = $_.Info
                                                        Algorithm =$_.Algorithm
                                                        OriginalAlgorithm =$_.OriginalAlgorithm
                                                        OriginalCoin = $_.OriginalCoin
                                                        Symbol = $_.WalletSymbol
                                                        ApiKey = $ApiKey
                                                        }
                                                    }
                                      }

                            $WalletStatus=@()
                            $WalletsToCheck |ForEach-Object {

                                            set_ConsolePosition 0 $YToWriteMessages
                                            "                                                                         "| Out-host 
                                            set_ConsolePosition 0 $YToWriteMessages

                                            if ($_.WalletMode -eq "WALLET") {writelog ("Checking "+$_.Abbname+" - "+$_.symbol) $logfile $true}
                                               else {writelog ("Checking "+$_.Abbname+" - "+$_.coin+' ('+$_.Algorithm+')') $logfile $true}
                                         

                                          
                                            $Ws = Get_Pools -Querymode $_.WalletMode -PoolsFilterList $_.Poolname -Info ($_)
                                            
                                            if ($_.WalletMode -eq "WALLET") {$Ws | Add-Member Wallet $_.User}
                                            else  {$Ws | Add-Member Wallet $_.Coin}

                                            $Ws | Add-Member PoolName $_.Poolname

                                            $Ws | Add-Member WalletSymbol $_.Symbol
                                            
                                            $WalletStatus += $Ws

                                            set_ConsolePosition 0 $YToWriteMessages
                                            "                                                                         "| Out-host 

                                            start-sleep 1 #no saturation of pool api


                                            
                                        } 


                            if ($FirstTotalExecution -eq $true) {$WalletStatusAtStart= $WalletStatus}
 
                            $WalletStatus | Add-Member BalanceAtStart [double]$null
                            $WalletStatus | ForEach-Object{
                                    $_.BalanceAtStart = ($WalletStatusAtStart |Where-Object wallet -eq $_.Wallet |Where-Object poolname -eq $_.poolname |Where-Object currency -eq $_.currency).balance
                                    }

                         }


 

                if ($Screen -eq "Wallets" -and $repaintScreen) {
                            
                            set_ConsolePosition 0 $YToWriteMessages
                            "Start Time: $StartTime                                                                                      " | Out-Host
                            "" | Out-Host 
                                                    

                            $WalletStatus | where-object Balance -gt 0 | Sort-Object poolname | Format-Table -Wrap -groupby poolname (
                                @{Label = "Coin"; Expression = {$_.WalletSymbol}}, 
                                @{Label = "Balance"; Expression = {$_.balance.tostring("n5")}; Align = 'right'},
                                @{Label = "IncFromStart"; Expression = {($_.balance - $_.BalanceAtStart).tostring("n5")}; Align = 'right'}
                                
                            ) | Out-Host
                        

                            $Pools  | where-object WalletMode -eq 'NONE' | Select-Object PoolName -unique | ForEach-Object {
                                "NO EXISTS API FOR POOL "+$_.PoolName+" - NO WALLETS CHECK" | Out-host 
                                }  

                            $repaintScreen=$false
                            }
                        
                
            }

            
        #############################################################    
        if ($Screen -eq "History" -and $repaintScreen) {                        

                 
                    
                    set_ConsolePosition 0 $YToWriteMessages
                    "Running Mode: $MiningMode" |out-host

                    set_ConsolePosition 0 $YToWriteData

                    #Display activated miners list
                    $ActiveMiners | Where-Object ActivatedTimes -GT 0 | Sort-Object -Descending LastTimeActive  | Format-Table -Wrap  (
                        @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},   
                        @{Label = "LastTime"; Expression = {$_.LastTimeActive}}, 
                        @{Label = "GroupName"; Expression = {$_.GroupName}}, 
                        @{Label = "Command"; Expression = {"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
                    )  | Out-Host


                    $repaintScreen=$false
                }

        #############################################################
  
        if ($Screen -eq "Stats" -and $repaintScreen) {                        

                    

                    set_ConsolePosition 0 $YToWriteMessages
                    "Start Time: $StartTime"
                    
                    set_ConsolePosition ($Host.UI.RawUI.WindowSize.Width-30) $YToWriteMessages

                    "Running Mode: $MiningMode" | Out-Host


                    set_ConsolePosition 0 $YToWriteData

                    #Display activated miners list
                    $ActiveMiners | Where-Object ActivatedTimes -GT 0 | Sort-Object @{expression="GroupName";Ascending=$true}, @{expression="LastTime";Descending=$true} | Format-Table -Wrap  -GroupBy GroupName (
                        @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},   
                        @{Label = "Algorithm"; Expression = {if ($_.AlgorithmDual -eq $null) {$_.Algorithm} else  {$_.Algorithm+ '|' + $_.AlgorithmDual}}},       
                        @{Label = "Pool"; Expression = {$_.PoolAbbName}},
                        @{Label = "Miner"; Expression = {$_.Name}}, 
                        @{Label = "Launch"; Expression = {$_.ActivatedTimes}},
                        @{Label = "Time"; Expression = {[string][int]$_.ActiveTime.TotalMinutes+" min"}},
                        @{Label = "Best"; Expression = {$_.BestTimes}},
                        @{Label = "Status"; Expression = {$_.Status}},
                        @{Label = "Last"; Expression = {$_.LastTimeActive}} 
                    ) | Out-Host


                    $repaintScreen=$false
                }
                
                 
 
                $FirstLoopExecution=$False

                #Loop for reading key and wait
             
                $KeyPressed=Timed_ReadKb 3 ('P','C','H','E','W','U','T','B','S','X')


            
                switch ($KeyPressed){
                    'P' {$Screen='PROFITS'}
                    'C' {$Screen='CURRENT'}
                    'H' {$Screen='HISTORY'}
                    'S' {$Screen='STATS'}
                    'E' {$ExitLoop=$true}
                    'W' {$Screen='WALLETS'}
                    'U' {if ($Screen -eq "WALLETS") {$WalletsUpdate=$null}}
                    'T' {if ($Screen -eq "PROFITS") {if ($ProfitsScreenLimit -eq $InitialProfitsScreenLimit) {$ProfitsScreenLimit=1000} else {$ProfitsScreenLimit=$InitialProfitsScreenLimit}}}
                    'B' {if ($Screen -eq "PROFITS") {if ($ShowBestMinersOnly -eq $true) {$ShowBestMinersOnly=$false} else {$ShowBestMinersOnly=$true}}}
                    'X' {set_WindowSize 165 60}
                    }

                if ($KeyPressed) {Clear-host;$repaintScreen=$true}
           
                if (((Get-Date) -ge ($LoopStarttime.AddSeconds($NextInterval)))  ) { #If time of interval has over, exit of main loop
                                $ActiveMiners | Where-Object Best -eq $true | ForEach-Object { #if a miner ends inteval without speed reading mark as failed
                                       if ($_.AnyNonZeroSpeed -eq $false) {$_.FailedTimes++;$_.status="Failed"}
                                    }
                                 break
                            } 

                if ($ExitLoop) {break} #forced exit

               ErrorsToLog $logfile
           
    
        }
    
    
    Remove-variable miners
    Remove-variable pools
    Get-Job -State Completed | Remove-Job
    [GC]::Collect() #force garbage recollector for free memory
    $FirstTotalExecution =$False

    
}

#-----------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------end of alwais running loop--------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------



Writelog "Program end" $logfile

$ActiveMiners | ForEach-Object { Kill_ProcessId $_.Process.Id}
    
#Stop-Transcript
