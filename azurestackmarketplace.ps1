#Update the two below vaules for your Azure Stack Environment
$ArmEndpoint = "https://adminmanagement.<dns zone>/"
$StackTenantID = "<GUID>"



$cred = Get-Credential

Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint $ArmEndpoint -ErrorAction Stop 
Login-AzureRmAccount -Environment "AzureStackAdmin" -Credential $cred -TenantId $StackTenantID #as someone with access to the default subscription

$activationRG = "azurestack-activation"
$bridgeactivation = Get-AzsAzureBridgeActivation -ResourceGroupName $activationRG 
$activationName = $bridgeactivation.Name

#Want all the extensions
$getExtensions = ((Get-AzsAzureBridgeProduct -ActivationName $activationName -ResourceGroupName $activationRG -ErrorAction SilentlyContinue -Verbose | Where-Object {($_.ProductKind -eq "virtualMachineExtension") -and ($_.Name -like "*microsoft*")}).Name) -replace "default/", ""

foreach ($extension in $getExtensions) 
{
    Write-Output "Checking for $extension"
    if (!$(Get-AzsAzureBridgeDownloadedProduct -Name $extension -ActivationName $activationName -ResourceGroupName $activationRG -ErrorAction SilentlyContinue))
    { 
        Write-Output "** Didn't find $extension in your gallery. Downloading from the Azure Stack Marketplace **"
        Invoke-AzsAzureBridgeProductDownload -ActivationName $activationName -Name $extension -ResourceGroupName $activationRG -Force -Confirm:$false
    }
}

#Get core images   PublisherDisplayName, PublisherIdentifier, Offer, Sku
$imagesrequired = @(@("Canonical","Canonical","UbuntuServer","16.04-LTS"),
                    @("Canonical","Canonical","UbuntuServer","18.04-LTS"),
                    @("Microsoft","MicrosoftWindowsServer","WindowsServer","2016-Datacenter"),
                    @("Microsoft","MicrosoftWindowsServer","WindowsServer","2016-Datacenter-Server-Core"),
                    @("Microsoft","MicrosoftWindowsServer","WindowsServer","2016-Datacenter-with-Containers"))

$getAllImages = Get-AzsAzureBridgeProduct -ActivationName $activationName -ResourceGroupName $activationRG | Where-Object {($_.ProductKind -eq "virtualMachine")}
foreach ($image in $imagesrequired)
{
    Write-Output "Checking for $($image[2])-$($image[3])"
    #Need to check the name of the latest
    $templist = $getAllImages | Where-Object {$_.PublisherDisplayName -eq $image[0] -and $_.Offer -eq $image[2] -and $_.Sku -eq $image[3] -and $_.DisplayName -notlike "*Pay as you*"}
    $templist = $templist | Sort-Object -Property ProductProperties -Descending
    $imagename = $templist[0].Name -replace "default/", ""  #is the latest
    #Write-Output "Checking for name $imagename"
    if (!$(Get-AzsAzureBridgeDownloadedProduct -ActivationName $activationName -ResourceGroupName $activationRG -Name $imagename -ErrorAction SilentlyContinue))
    { 
        Write-Output "** Didn't find image in your gallery. Downloading from the Azure Stack Marketplace **"
        Invoke-AzsAzureBridgeProductDownload -ActivationName $activationName -Name $imagename -ResourceGroupName $activationRG -Force -Confirm:$false
    }
}

#Now check for multiple versions of something and clean the old

#Get what is installed
$allinstalled = Get-AzsAzureBridgeDownloadedProduct -ActivationName $activationName -ResourceGroupName $activationRG
$allinstalled = $allinstalled | Sort-Object -Property DisplayName, ProductProperties -Descending #want newest first as we'll look for matching and remove the second
#$allinstalled | fl displayname, offerversion, ProductProperties, PublisherDisplayName, PublisherIdentifier, Offer, SKU, Name

$prevDisplayName = "Not going to match"
$prevEntry = $null
foreach($installed in $allinstalled)
{
    #see if name matches the previous, i.e. same image
    if($installed.DisplayName -eq $prevDisplayName)
    {
        #Lets remove it 
        Write-Output "** Found an older version of $($installed.DisplayName) **"
        Write-Output "   Previous version is $($installed.ProductProperties.Version) - $($installed.Name)"
        Write-Output "   Current version is $($prevEntry.ProductProperties.Version) - $($prevEntry.Name)"
        $Readhost = Read-Host " Do you want to delete previous version ($($installed.ProductProperties.Version)) (y/n)?"
        Switch ($ReadHost) 
         { 
           Y {Write-host " Yes, Removing old version"; Remove-AzsAzureBridgeDownloadedProduct -Name $installed.Name -ActivationName $activationName -ResourceGroupName $activationRG -Force -Confirm:$false -ErrorAction Continue} 
           N {Write-Host " No, Not removing"} 
           Default {Write-Host " Default, Not removing"} 
         }

        Write-Output ""
    }
    $prevDisplayName = $installed.DisplayName
    $prevEntry = $installed
}
