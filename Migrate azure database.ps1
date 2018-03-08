

# Login in Azure and select Subscription

$SubscriptionName = "Subscription name"
#Login-AzureRmAccount
Get-AzureRmSubscription –SubscriptionName $SubscriptionName | Select-AzureRmSubscription



$targetServerLoginID = "login"
$Location = "West Europe"
$targetServerLoginPassword = "password"



# Seting Up things
$ProjectName = "secretproject"
$EnvironmentName = "dev"

# Database setup
$DbUserName = "$($ProjectName)SqlUser"
$DbPassword ="SqlPassword"


$ServerName = "$($ProjectName)-$($EnvironmentName)-sql-eu"
#$SqlServer = New-AzureRMSQLServer -ServerName $ServerName -Location $Location -SqlAdministratorCredentials $SqlServerDbPassword -ResourceGroupName "Default-SQL-NorthEurope"


New-AzureRmSqlDatabaseCopy -ResourceGroupName "tecapp-prod-eu" -ServerName "tecapp-prod-sql-eu" -DatabaseName "tecapp.copy" -CopyResourceGroupName "tecapp-prod-eu" -CopyServerName "tecapp-prod-sql-eu" -CopyDatabaseName "tecapp.main"


$uri = "https://management.core.windows.net:8443/" + $sourceSubscriptionID + "/services" + "/sqlservers/servers/" + $ServerName + "?op=ChangeSubscription" 

Invoke-RestMethod -Uri $uri -CertificateThumbPrint $certThumbprint -ContentType $contenttype -Method $method -Headers $headers -Body $body 