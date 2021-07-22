param
(
    [string]
    $configVersion, #configversion of Geneva WarmPath

    [string]
    $vmName,

    [string]
    $storageAccountName, #storage account where the geneva monitoring .zip is uploaded

    [string]
    $storageContainer, #container name inside the storage account

    [string]
    $genevaAgentBlobName,

    [string]
    $genevaAccount,

    [string]
    $genevaEnvironment,

    [string]
    $genevaNamespace,

    [string]
    $genevaRegion,

    [string]
    $certName, #certName of Geneva uploaded in KeyVault

    [string]
    $SASToken
)

try
{
    <####################################
    $configVersion             = "1.1"
    $vmName                    = "TestvmName"
    $StorageAccountName        = "genevastroageeast2"
    $storageContainer          = "genevacontainer"
    $genevaAgentBlobName       = "GenevaAgent.zip"
    $genevaAccount             = "ENSNONPRODASSERTS"
    $genevaEnvironment         = "DiagnosticsPROD"
    $genevaNamespace           = "ENSNONPRODASSERTS" 
    $genevaRegion              = "WestUS"
    $certName                  = "enssrekeyvaultgeneva-genevacert.pfx"
    $SASToken                  = "?sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacuptfx&se=2021-07-31T19:46:59Z&st=2021-07-13T11:46:59Z&spr=https&sig=zoizbZYRvXU0ZqS%2FDWUoZAFQ7mGOf4it3GW8XwNd9%2F8%3D"
    ####################################>


    $genevaPath = "C:\GenevaAgent"
    $storageBlobPath = "C:\StorageAccountBlob"
    $certPath = "$storageBlobPath\$($certName)"
    $role = $vmName
    $tenant = $vmName
    $roleInstance = $env:computername
    $logsPath = "C:\$($vmName)-SetUpGenevaLogs.txt"

    ###### CREATE BLOB AND GENEVA DIRECTORY ###################

    if(Test-Path $storageBlobPath)
    {
        Remove-Item -Path $storageBlobPath -Recurse
    }

    if(Test-Path $genevaPath)
    {
        Remove-Item -Path $genevaPath -Recurse
    }

    mkdir $storageBlobPath
    mkdir $genevaPath

    Add-Content -Path $logsPath -Value "$(Get-Date) - Vm Name : $vmName"

    ##### DOWNLOAD GENEVA AGENT BINARIES ######################
    Add-Content -Path $logsPath -Value "Downloading Geneva Agent"
    $genevaFilePath = "$storageBlobPath\GenevaAgent.zip"
    Invoke-WebRequest -Uri "https://$($storageAccountName).blob.core.windows.net/$($storageContainer)/$($genevaAgentBlobName)$($SASToken)" -OutFile $genevaFilePath
   
    ##### INSTALL CERTIFICATE #################################
    Invoke-WebRequest -Uri "https://$($storageAccountName).blob.core.windows.net/$($storageContainer)/$($certName)$($SASToken)" -OutFile $certPath  
    Import-PfxCertificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\My
    $certThumbprint = (Get-PfxData -FilePath $certPath).EndEntityCertificates.Thumbprint
    #$certThumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match $certName}).Thumbprint;
    Add-Content -Path $logsPath -Value "Installing Geneva Agent"
    Expand-Archive -Path $genevaFilePath -DestinationPath $genevaPath
    
    ##### CONFIGURE AND RUN GENEVA AGENT ######################

     Set-Location $genevaPath

     Add-Content -Path $logsPath -Value "Configuring Geneva Agent"
     $configVersionPattern  = '\s*(\d+[.]\d+|<ConfigVersion>)'
     $launchAgentContent = Get-Content -path $genevaPath\LaunchAgent.cmd -Raw
     $launchAgentContent = $launchAgentContent -replace "<TenantName>", $tenant
     $launchAgentContent = $launchAgentContent -replace "<RoleName>", $role
     $launchAgentContent = $launchAgentContent -replace "<RoleInstance>",$roleInstance
     $launchAgentContent = $launchAgentContent -replace $configVersionPattern, $configVersion
     $launchAgentContent = $launchAgentContent -replace "<GenevaPath>", $genevaPath
     $launchAgentContent = $launchAgentContent -replace "<CertThumbprint>",$certThumbprint
     $launchAgentContent = $launchAgentContent -replace "<GenevaAccount>",$genevaAccount
     $launchAgentContent = $launchAgentContent -replace "<GenevaNamespace>",$genevaNamespace
     $launchAgentContent = $launchAgentContent -replace "<GenevaEnvironment>",$genevaEnvironment
     $launchAgentContent = $launchAgentContent -replace "<GenevaRegion>",$genevaRegion
     $launchAgentContent| Set-Content $genevaPath\LaunchAgent.cmd

     Add-Content -Path $logsPath -Value "Running Geneva Agent"

     $taskName="GenevaMonitoring"
     $taskWorkingDir = $genevaPath
     $taskExecution = "$genevaPath\LaunchAgent.cmd"

     $taskExist = (Get-ScheduledTask | Where-Object { $_.TaskName -eq $taskName } | Measure-Object).Count -gt 0

     if(-not($taskExist)) {
         $taskAction = New-ScheduledTaskAction -Execute $taskExecution -WorkingDirectory $taskWorkingDir
         $taskTrigger = New-ScheduledTaskTrigger -AtStartup
         $taskPrincipal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
         $taskSetting = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries
         $taskDefinition = New-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSetting
         $task = Register-ScheduledTask -TaskName $taskName -InputObject $taskDefinition

         Start-ScheduledTask -TaskName $taskName
     }

     Add-Content -Path $logsPath -Value "Geneva Agent Started"

}
catch
{
     #Error source File:
     $errorfile = "C:\$($vmName)-SetUpGenevaErrorLogs.txt"

     Set-Content -Path $errorfile -value $_       
}