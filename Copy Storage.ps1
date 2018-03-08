
$SourceStorageAccount = "xxxxxxxx"
$SourceStorageKey = "xxxxxxxx_key"
$DestStorageAccount = "yyyyyyy"
$DestStorageKey = "yyyyyyy_key"

$SourceStorageContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $SourceStorageKey
$DestStorageContext = New-AzureStorageContext –StorageAccountName $DestStorageAccount -StorageAccountKey $DestStorageKey


$containers = Get-AzureStorageContainer -Context $SourceStorageContext
foreach( $srcContainer in $containers ) {    
    Write-Output "$($srcContainer.Name)"

    $destContainer = Get-AzureStorageContainer -Context $DestStorageContext -Name $srcContainer.Name -ErrorAction SilentlyContinue
    if( !$destContainer ) {
        $destContainer = New-AzureStorageContainer -Context $DestStorageContext -Name $srcContainer.Name
    }

    
    $Blobs = Get-AzureStorageBlob -Context $SourceStorageContext -Container $srcContainer.Name
    $BlobCpyAry = @() #Create array of objects

    #Do the copy of everything
    foreach ($Blob in $Blobs)
    {
       Write-Output "Moving $Blob.Name"
       $BlobCopy = Start-CopyAzureStorageBlob -Context $SourceStorageContext -SrcContainer $srcContainer.Name -SrcBlob $Blob.Name `
          -DestContext $DestStorageContext -DestContainer $destContainer.Name -DestBlob $Blob.Name
       $BlobCpyAry += $BlobCopy
    }

    #Check Status
    foreach ($BlobCopy in $BlobCpyAry)
    {
       #Could ignore all rest and just run $BlobCopy | Get-AzureStorageBlobCopyState but I prefer output with % copied
       $CopyState = $BlobCopy | Get-AzureStorageBlobCopyState
       $Message = $CopyState.Source.AbsolutePath + " " + $CopyState.Status + " {0:N2}%" -f (($CopyState.BytesCopied/$CopyState.TotalBytes)*100) 
       Write-Output $Message
    }
}


Get-AzureStorageContainer -Context $DestStorageContext

