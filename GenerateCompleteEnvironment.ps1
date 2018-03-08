
###################################################     CUSTOM TYPES     ########################################

$Type_RegionConfigurationSettings = @"
    using System;

    public class RegionConfigurationSettings
    {
        public String ResourceGroupName;
        public String AzureWebJobsStorageConnection;
        public String RedisCacheConnection;  
        public String RegionId;
        public String Location;  
        public String secretprojectContext;
        public String secretprojectContextRead;
        public String secretprojectReporting;    
    }
"@

$Type_NetworkConfigurationSettings = @"
    using System;

    public class NetworkConfigurationSettings
    {
        public String ResourceGroupGlobalName;
        public String TrafficManagerProfileApiName;
        public String TrafficManagerProfileApiPortalName;
        public String TrafficManagerProfilePortalName;
        public String FqdnApi;
        public String FqdnApiPortal;
        public String FqdnPortal;
    }
"@

if (-not ([System.Management.Automation.PSTypeName]'RegionConfigurationSettings').Type)
{
    Add-Type -TypeDefinition $Type_RegionConfigurationSettings
}
if (-not ([System.Management.Automation.PSTypeName]'NetworkConfigurationSettings').Type)
{
    Add-Type -TypeDefinition $Type_NetworkConfigurationSettings
}
###################################################     END CUSTOM TYPES     ########################################



#####################################################     FUNCTIONS     ########################################

# Global region: traffic managers, application insights
function Create-Global-ResourceGroup( $Location ) {
    # Create RG
    $ConfigNetwork.ResourceGroupGlobalName = "$($ProjectName)-$($EnvironmentName)-global"
    Create-Resource-Group $ConfigNetwork.ResourceGroupGlobalName $Location

    # Create TfManagers
    # API
    $ConfigNetwork.TrafficManagerProfileApiName = "$($ProjectName)-$($EnvironmentName)-api" 
    Create-Traffic-Manager $Location $ConfigNetwork.TrafficManagerProfileApiName
    # APIPORTAL
    $ConfigNetwork.TrafficManagerProfileApiPortalName = "$($ProjectName)-$($EnvironmentName)-apiportal" 
    Create-Traffic-Manager $Location $ConfigNetwork.TrafficManagerProfileApiPortalName
    # PORTAL
    $ConfigNetwork.TrafficManagerProfilePortalName = "$($ProjectName)-$($EnvironmentName)-portal" 
    Create-Traffic-Manager $Location $ConfigNetwork.TrafficManagerProfilePortalName
}

function Create-Traffic-Manager( $Location, $TrafficManagerProfileName) {
    $trafficManager = Get-AzureRmTrafficManagerProfile -Name $TrafficManagerProfileName -ResourceGroupName $ConfigNetwork.ResourceGroupGlobalName -ErrorAction SilentlyContinue
    if(!$trafficManager)
    {
        Write-Host "Creating Traffic Manager '$TrafficManagerProfileName' in location '$Location'";
        New-AzureRmTrafficManagerProfile -Name $TrafficManagerProfileName -ResourceGroupName $ConfigNetwork.ResourceGroupGlobalName -TrafficRoutingMethod $RoutingStrategy -RelativeDnsName $TrafficManagerProfileName -Ttl 30 -MonitorProtocol HTTP -MonitorPort 80 -MonitorPath "/probe.html"
    }
    else{
        Write-Host "Traffic manager already exists '$TrafficManagerProfileName'";
    }
}

function Create-Resource-Group( [string] $ResourceGroupName, $Location ) {
    $resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if(!$resourceGroup)
    {
        Write-Host "Creating resource group '$ResourceGroupName' in location '$Location'";
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
    }

    return $resourceGroup
}

function Create-Sql-Server {
    # Create a SQL Database Server
    $ServerName = "$($ProjectName)-$($EnvironmentName)-sql-$($Config.RegionId)"
    
    $SqlServer = Get-AzureRMSQLServer -ServerName $ServerName -ResourceGroupName $Config.ResourceGroupName -ErrorAction SilentlyContinue
    if(!$SqlServer)
    {        
        $SqlServer = New-AzureRMSQLServer -ServerName $ServerName -Location $Config.Location -SqlAdministratorCredentials $SqlServerDbPassword -ResourceGroupName $Config.ResourceGroupName

        # Create Firewall Rule for SQL Database Server
        $IP = "10.10.10.110" 
        New-AzureRmSqlServerFirewallRule -FirewallRuleName "Secret Office" -StartIPAddress $IP -EndIPAddress $IP -ServerName $ServerName -ResourceGroupName $Config.ResourceGroupName
        
        # Create Databases
        # Create SQL Database in SQL Database Server
        New-AzureRMSQLDatabase -ServerName $ServerName -DatabaseName "$($ProjectName).reporting" -ResourceGroupName $Config.ResourceGroupName
        New-AzureRMSQLDatabase -ServerName $ServerName -DatabaseName "$($ProjectName).main" -ResourceGroupName $Config.ResourceGroupName
    }
}

function Create-Redis {
    $RedisName = "$($ProjectName)-$($EnvironmentName)-$($Config.RegionId)"

    $Redis = Get-AzureRmRedisCache -Name $RedisName -ResourceGroupName $Config.ResourceGroupName -ErrorAction SilentlyContinue
    if(!$Redis)
    {           
        $Redis = New-AzureRmRedisCache -ResourceGroupName  $Config.ResourceGroupName  -Name $RedisName -Location $Config.Location -Sku "Basic" -Size "C0"        
    }
    $RedisKeys = Get-AzureRmRedisCacheKey -Name $RedisName -ResourceGroupName $Config.ResourceGroupName
    $Config.RedisCacheConnection = "$($Redis.Name).redis.cache.windows.net:6380,password=$($RedisKeys.PrimaryKey),ssl=True,abortConnect=False,allowAdmin=true"
}

function Create-Storage {
    $StorageName = "$($ProjectName)$($EnvironmentName)storage$($Config.RegionId)"

    $storage = Get-AzureRmStorageAccount -Name $StorageName -ResourceGroupName $Config.ResourceGroupName -ErrorAction SilentlyContinue
    if(!$storage)
    {       
                
        New-AzureRmStorageAccount -ResourceGroupName $Config.ResourceGroupName -Name $StorageName -Location $Config.Location -SkuName "Standard_LRS"    
    }

    $StorageKey = (Get-AzureRmStorageAccountKey -Name $StorageName -ResourceGroupName $Config.ResourceGroupName)[0].Value
    $Config.AzureWebJobsStorageConnection = "DefaultEndpointsProtocol=https;AccountName=$($StorageName);AccountKey=$($StorageKey);EndpointSuffix=core.windows.net"
}

function Create-Region-Structure( $ConfigNetwork ) {
    # Create the resource group
    $Config.ResourceGroupName = "$($ProjectName)-$($EnvironmentName)-$($Config.RegionId)"
    Create-Resource-Group $Config.ResourceGroupName $Config.Location
    
    
    # Creates the Storage account        
    Create-Storage
    # Create the redis cache       
    Create-Redis 
    # Creates the Sql Server    
    # Create-Sql-Server 


    # Create the App Service plan.
    $ServicePlanName = "$($ProjectName)-$($EnvironmentName)-ServicePlan-$($Config.RegionId)"
    $servicePlan = Get-AzureRmAppServicePlan -Name $ServicePlanName
    if(!$servicePlan) {
        $servicePlan = New-AzureRmAppServicePlan -Name $ServicePlanName -Location $Config.Location -ResourceGroupName $Config.ResourceGroupName -Tier Standard
    }
    

    # Create the App Services
    $connectionStrings = @{
	    secretprojectContextRead = @{ Type = "SQLAzure"; Value = $Config.secretprojectContextRead};
	    secretprojectContext = @{ Type = "SQLAzure"; Value = $Config.secretprojectContext};
	    secretprojectReporting = @{ Type = "SQLAzure"; Value = $Config.secretprojectReporting};
	    AzureWebJobsStorage = @{ Type = "Custom"; Value = $Config.AzureWebJobsStorageConnection};
	    RedisCache = @{ Type = "Custom"; Value = $Config.RedisCacheConnection}
    }        
    $ApiAppService = Create-App-Service "api" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfileApiName $connectionStrings
    
    # APIPORTAL  
    $connectionStrings = @{
	    secretprojectContextRead = @{ Type = "SQLAzure"; Value = $Config.secretprojectContextRead};
	    secretprojectContext = @{ Type = "SQLAzure"; Value = $Config.secretprojectContext};
    }  
    $ApiPortalAppService = Create-App-Service "apiportal" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfileApiPortalName $connectionStrings
    
    # PORTAL
    $PortalAppService = Create-App-Service "portal" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfilePortalName

}

function Create-App-Service( $AppName, $ServicePlanName, $ConfigNetwork, $TrafficManagerProfileName, $connectionStrings ) {
    $AppServiceName = "$($ProjectName)-$($EnvironmentName)-$($AppName)-$($Config.RegionId)" 

    $appService = Get-AzureRmWebApp -Name $AppServiceName -ResourceGroupName $Config.ResourceGroupName -ErrorAction SilentlyContinue
    if(!$appService)
    {
        Write-Host "Creating App Service '$AppServiceName' in location '$Config.Location)";        
        $appService = New-AzureRmWebApp -Name $AppServiceName -Location $Config.Location -AppServicePlan $ServicePlanName -ResourceGroupName $Config.ResourceGroupName     
    }

    # Create a deployment slot with the name "staging".
    $appServiceSlot = Get-AzureRmWebAppSlot -Name $AppService.SiteName -ResourceGroupName $Config.ResourceGroupName
    if(!$appServiceSlot) {
        $appServiceSlot = New-AzureRmWebAppSlot -Name $AppService.SiteName -ResourceGroupName $Config.ResourceGroupName -Slot "staging"
    }      

    Configure-App-Service $appService $appServiceSlot $ConfigNetwork $TrafficManagerProfileName $connectionStrings

    return $appService
}

function Configure-App-Service( $AppService, $appServiceSlot, $ConfigNetwork, $TrafficManagerProfileName, $connectionStrings) {
    if($connectionStrings) {
        $AppService | Set-AzureRmWebApp -ResourceGroupName $appService.ResourceGroup -ConnectionStrings $connectionStrings
        Set-AzureRmWebAppSlot -ResourceGroupName $AppService.ResourceGroup -Name $AppService.Name -Slot "staging" -ConnectionStrings $connectionStrings        
    }

    $AppServiceSiteConfig = $AppService.SiteConfig
    $WebAppPropertiesObject = @{
	    "SiteConfig" = @{
		    "AlwaysOn" = $true;
		    "PhpVersion" = "Off";
	    };
    }
    $AppService | Set-AzureRmResource -PropertyObject $WebAppPropertiesObject -Force
    $appServiceSlot | Set-AzureRmResource -PropertyObject $WebAppPropertiesObject -Force
    
    Set-AzureRmWebApp -ResourceGroupName $Config.ResourceGroupName -Name $AppService.Name -AppSettings @{"ASPNETCORE_ENVIRONMENT"="Debug-DEV"} -DefaultDocuments {index.html}
    Set-AzureRmWebAppSlot -ResourceGroupName $AppService.ResourceGroup -Name $AppService.Name -Slot "staging" -AppSettings @{"ASPNETCORE_ENVIRONMENT"="Staging-EU"} -DefaultDocuments {index.html}

    # Create trafficmanager endpoint
    $TrafficManagerProfile = Get-AzureRmTrafficManagerProfile -Name $TrafficManagerProfileName -ResourceGroupName $ConfigNetwork.ResourceGroupGlobalName
    $endpointConfig = $TrafficManagerProfile.Endpoints |  Where-Object { $_.Name -match $AppService.SiteName }
    if(!$endpointConfig) {
        Add-AzureRmTrafficManagerEndpointConfig -EndpointName $AppService.SiteName -TrafficManagerProfile $TrafficManagerProfile -Type AzureEndpoints -TargetResourceId $AppService.Id -EndpointStatus Enabled
        Set-AzureRmTrafficManagerProfile -TrafficManagerProfile $TrafficManagerProfile
    }
    
    
    # Add a custom domain name to the web app. 
    $HostName = "$($TrafficManagerProfileName).trafficmanager.net"
    try {
        Set-AzureRmWebApp -ResourceGroupName $Config.ResourceGroupName -Name $AppService.Name -HostNames @($ConfigNetwork.FqdnApi, $HostName)
    } catch {}


    # ENABLE CORS, also staging slot
}

function Configure-Failover {
     $failoverGroupName = "$($ProjectName)-failover-$($EnvironmentName)"
     $failover = Get-AzureRMSqlDatabaseFailoverGroup -FailoverGroupName $failoverGroupName -ResourceGroupName "$($ProjectName)-$($EnvironmentName)-eu" -ServerName "$($ProjectName)-$($EnvironmentName)-sql-eu"  -ErrorAction SilentlyContinue
     if(!$failover) {
         New-AzureRMSqlDatabaseFailoverGroup `
              -ResourceGroupName "$($ProjectName)-$($EnvironmentName)-eu" -ServerName "$($ProjectName)-$($EnvironmentName)-sql-eu" `
              -PartnerResourceGroupName "$($ProjectName)-$($EnvironmentName)-zn" -PartnerServerName "$($ProjectName)-$($EnvironmentName)-sql-zn" `
              -FailoverGroupName "$($ProjectName)-failover-$($EnvironmentName)" -FailoverPolicy Automatic -GracePeriodWithDataLossHours 1
    
         $primaryServer = Get-AzureRmSqlServer -ResourceGroupName "$($ProjectName)-$($EnvironmentName)-eu" -ServerName "$($ProjectName)-$($EnvironmentName)-sql-eu"
         $failoverGroup = $primaryServer | Add-AzureRmSqlDatabaseToFailoverGroup -FailoverGroupName $failoverGroupName -Database ($primaryServer | Get-AzureRmSqlDatabase)
     }
}

#####################################################   END FUNCTIONS     ########################################

# to delete the everything:
# Remove-AzureRmResourceGroup -Name groupName -Force;


# Login in Azure and select Subscription

$SubscriptionName = "Subscription name"
#Login-AzureRmAccount
Get-AzureRmSubscription –SubscriptionName $SubscriptionName | Select-AzureRmSubscription


# Seting Up things
$ProjectName = "secretproject"
$EnvironmentName = "prod"

$ConfigEu = New-Object RegionConfigurationSettings
$ConfigEu.Location = "West Europe"
$ConfigEu.RegionId = "eu"

$ConfigZn = New-Object RegionConfigurationSettings
$ConfigZn.Location = "East Asia"
$ConfigZn.RegionId = "zn"

# Traffic Managers
$ConfigNetwork = New-Object NetworkConfigurationSettings
$RoutingStrategy = "Performance"

# Database setup
$DbUserName = "$($ProjectName)SqlAdminUser"
$DbPassword ="SqlAdminUserPassword"
$SqlServerDbPassword = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DbUserName,(ConvertTo-SecureString -String $DbPassword -AsPlainText -Force)

# Failover
$PrimaryFailoverName = "$($ProjectName)-failover-$($EnvironmentName).database.windows.net"
$SecondaryFailoverName = "$($ProjectName)-failover-$($EnvironmentName).secondary.database.windows.net"

$ConfigEu.secretprojectContext = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigEu.secretprojectContextRead = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigEu.secretprojectReporting = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).reporting;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

$ConfigZn.secretprojectContext = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigZn.secretprojectContextRead = "Server=tcp:$($SecondaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigZn.secretprojectReporting = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).reporting;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"



# DNS Stuff
$ConfigNetwork.FqdnApi = "xxxx.secretcompany.net"
$ConfigNetwork.FqdnApiPortal = "yyyy.secretcompany.net"
$ConfigNetwork.FqdnPortal = "zzzz.secretcompany.net"


# Global region
Create-Global-ResourceGroup $ConfigEu.Location

# EU region
$Config = $ConfigEu
 Create-Region-Structure $ConfigNetwork
# ZN region
$Config = $ConfigZn
Create-Region-Structure $ConfigNetwork

# Sql failover
# Establish Active Geo-Replication
Configure-Failover
