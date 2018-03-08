
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

function Setup-Region-AppServices( $ConfigNetwork ) {
    
    $Config.ResourceGroupName = "$($ProjectName)-$($EnvironmentName)-$($Config.RegionId)"

    $RedisName = "$($ProjectName)-$($EnvironmentName)-$($Config.RegionId)"
    $RedisKeys = Get-AzureRmRedisCacheKey -Name $RedisName -ResourceGroupName $Config.ResourceGroupName
    $Config.RedisCacheConnection = "$($RedisName).redis.cache.windows.net:6380,password=$($RedisKeys.PrimaryKey),ssl=True,abortConnect=False,allowAdmin=true"

    $StorageName = "$($ProjectName)$($EnvironmentName)storage$($Config.RegionId)"
    $storage = Get-AzureRmStorageAccount -Name $StorageName -ResourceGroupName $Config.ResourceGroupName -ErrorAction SilentlyContinue    
    $StorageKey = (Get-AzureRmStorageAccountKey -Name $StorageName -ResourceGroupName $Config.ResourceGroupName)[0].Value
    $Config.AzureWebJobsStorageConnection = "DefaultEndpointsProtocol=https;AccountName=$($StorageName);AccountKey=$($StorageKey);EndpointSuffix=core.windows.net"


    # Create the App Services
    $connectionStrings = @{
	    secretprojectContextRead = @{ Type = "SQLAzure"; Value = $Config.secretprojectContextRead};
	    secretprojectContext = @{ Type = "SQLAzure"; Value = $Config.secretprojectContext};
	    secretprojectReporting = @{ Type = "SQLAzure"; Value = $Config.secretprojectReporting};
	    AzureWebJobsStorage = @{ Type = "Custom"; Value = $Config.AzureWebJobsStorageConnection};
	    RedisCache = @{ Type = "Custom"; Value = $Config.RedisCacheConnection}
    }
    $ApiAppService = Setup-App-Service "api" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfileApiName $connectionStrings
    
    # APIPORTAL
        $connectionStrings = @{
	    secretprojectContextRead = @{ Type = "SQLAzure"; Value = $Config.secretprojectContextRead};
	    secretprojectContext = @{ Type = "SQLAzure"; Value = $Config.secretprojectContext};
    }    
    $ApiPortalAppService = Setup-App-Service "apiportal" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfileApiPortalName $connectionStrings
    
    # PORTAL
    $PortalAppService = Setup-App-Service "portal" $ServicePlanName $ConfigNetwork $ConfigNetwork.TrafficManagerProfilePortalName

}

function Setup-App-Service( $AppName, $ServicePlanName, $ConfigNetwork, $TrafficManagerProfileName, $connectionStrings ) {
    $AppServiceName = "$($ProjectName)-$($EnvironmentName)-$($AppName)-$($Config.RegionId)" 

    $appService = Get-AzureRmWebApp -Name $AppServiceName -ResourceGroupName $Config.ResourceGroupName
    $appServiceSlot = Get-AzureRmWebAppSlot -Name $AppService.SiteName -ResourceGroupName $Config.ResourceGroupName

       
    if($connectionStrings) {
        $AppService | Set-AzureRmWebApp -ResourceGroupName $appService.ResourceGroup -ConnectionStrings $connectionStrings
        Set-AzureRmWebAppSlot -ResourceGroupName $AppService.ResourceGroup -Name $AppService.Name -Slot "staging" -ConnectionStrings $connectionStrings        
    }
    <# 
    $AppServiceSiteConfig = $AppService.SiteConfig
    $WebAppPropertiesObject = @{
	    "SiteConfig" = @{
		    "AlwaysOn" = $true;
		    "PhpVersion" = "Off";
	    };
    }
    #$AppService | Set-AzureRmResource -PropertyObject $WebAppPropertiesObject -Force
    $appServiceSlot | Set-AzureRmResource -PropertyObject $WebAppPropertiesObject -Force
    #>
    
    # Sticky 
    Set-AzureRmWebAppSlotConfigName  -Name $AppService.Name -ResourceGroupName $Config.ResourceGroupName -ConnectionStringNames ["ASPNETCORE_ENVIRONMENT"]

    Set-AzureRmWebApp -ResourceGroupName $Config.ResourceGroupName -Name $AppService.Name -AppSettings @{"ASPNETCORE_ENVIRONMENT"=$($EnvironmentName)} -DefaultDocuments {index.html}
    Set-AzureRmWebAppSlot -ResourceGroupName $AppService.ResourceGroup -Name $AppService.Name -Slot "staging" -AppSettings @{"ASPNETCORE_ENVIRONMENT"="$($EnvironmentName)-staging"} -DefaultDocuments {index.html}

   <#  
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
        Set-AzureRmWebApp -ResourceGroupName $Config.ResourceGroupName -Name $AppService.Name -HostNames @($ConfigNetwork.FqdnApi, $HostName) -ErrorAction SilentlyContinue
    } catch {}

    
    # Add IP security, also staging slot
    # ENABLE CORS, also staging slot

    #>
}


#####################################################   END FUNCTIONS     ########################################


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


# Failover
$PrimaryFailoverName = "$($ProjectName)-failover-$($EnvironmentName).database.windows.net"
$SecondaryFailoverName = "$($ProjectName)-failover-$($EnvironmentName).secondary.database.windows.net"

$ConfigEu.secretprojectContext = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigEu.secretprojectContextRead = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigEu.secretprojectReporting = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

$ConfigZn.secretprojectContext = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigZn.secretprojectContextRead = "Server=tcp:$($SecondaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$ConfigZn.secretprojectReporting = "Server=tcp:$($PrimaryFailoverName),1433;Initial Catalog=$($ProjectName).main;Persist Security Info=False;User ID=$($DbUserName);Password=$($DbPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"



# DNS Stuff
$ConfigNetwork.FqdnApi = "secretproject-prod-api.secretcompany.net"
$ConfigNetwork.FqdnApiPortal = "secretproject-prod-apiportal.secretcompany.net"
$ConfigNetwork.FqdnPortal = "secretproject-prod-portal.secretcompany.net"


$ConfigNetwork.ResourceGroupGlobalName = "$($ProjectName)-$($EnvironmentName)-global"
$ConfigNetwork.TrafficManagerProfileApiName = "$($ProjectName)-$($EnvironmentName)-api" 
$ConfigNetwork.TrafficManagerProfileApiPortalName = "$($ProjectName)-$($EnvironmentName)-apiportal" 
$ConfigNetwork.TrafficManagerProfilePortalName = "$($ProjectName)-$($EnvironmentName)-portal" 


# Global region
# Create-Global-ResourceGroup $ConfigEu.Location

# EU region
$Config = $ConfigEu
Setup-Region-AppServices $ConfigNetwork
# ZN region
$Config = $ConfigZn
Setup-Region-AppServices $ConfigNetwork
