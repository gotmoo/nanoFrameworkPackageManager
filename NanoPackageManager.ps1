function Add-NanoNugetPackage() {
    param(
        [Parameter(Position = 0, mandatory = $true)]    
        [string]$nugetPackage ,
        [ValidateScript({
                if ( -Not ($_ | Test-Path) ) {
                    throw "File or folder does not exist"
                }
                if ($_ -inotmatch "(\.nfproj)") {
                    throw "The file specified in the projectFile argument must be of type nfProj"
                }
                return $true
            })]
        [string]$projectFile,
        [string]$nugetLocation = "nuget.exe"
    )
    $startLocation = Get-Location
    try { Invoke-Expression $nugetLocation | Out-Null } catch { throw "Nuget.exe can't be found. Please make it available on your system in path or provide it as an argument." }

    if ($null -like $ProjectFile) {
        $ProjectFiles = Get-ChildItem "*.nfproj"
        $ProjectFileCount = ($ProjectFiles | Measure-Object).Count
        if ($ProjectFileCount -eq 0) {
            throw "No project found in current directory. Please specify project path. Please specify the project file name using the -ProjectFile argument."
            break
        }
        elseif ($ProjectFileCount -gt 1) {
            throw "More than one project file found in the current directory. Please specify the project file name using the -ProjectFile argument."
            break
        } 
        $projectFileObject = get-item $ProjectFiles.FullName
    }
    else {
        if (![System.IO.Path]::IsPathRooted($projectFile)) {
            $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($pwd, $projectFile))
            $projectFileObject = get-item $Path
        }
        else {
            throw "Please provide an absolute path on the local system."
            break
        }
    }
    
    # Open the project file to see if this is a Nano Project
    [xml]$xmlNfProj = Get-Content $projectFileObject.FullName
    # Create a namespace manager and add the default namespace
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlNfProj.NameTable)
    $nsManager.AddNamespace("ns", "http://schemas.microsoft.com/developer/msbuild/2003")

    # Use SelectNodes with the namespace manager and the modified XPath expression
    if ($null -eq ($xmlNfProj.SelectNodes("//ns:PropertyGroup[@Label='Globals']", $nsManager)).NanoFrameworkProjectSystemPath ) {
        throw "The selected project $projectFile is not a nanoFramework project file."
    }


    $packageConfigFilePath = Join-Path $projectFileObject.DirectoryName "packages.config" 
    [xml]$packageConfig = Get-Content $packageConfigFilePath

    #Connect to nuget HQ to find index search locations, and try all of them
    $nugetIndex = Invoke-RestMethod https://api.nuget.org/v3/index.json
    foreach ( $querySource in $nugetIndex.resources | Where-Object { $_."@type" -eq "SearchQueryService" }) {
        try {
            $searchUri = $querySource."@id" + "?q=" + $nugetPackage
            $restResult = Invoke-RestMethod -Uri $searchUri 
            $searchResult = $restResult.data | Where-Object { $_.id -eq $nugetPackage } 
            #Break out of the loop when data has been retrieved
            break
        }
        catch {
            Write-Warning "Not able to search at " + $querySource."@id" 
            <#Do this if a terminating exception happens#>
        }
    }
    if (($searchResult | Measure-Object).count -eq 0) {
        throw "No results were found on NuGet for " + $nugetPackage
    }
    elseif (($searchResult | Measure-Object).count -gt 1) {
        $msg = $("Too many results found`n" ) + ($searchResult | Select-Object id, version, title | Format-Table -AutoSize | Out-String)
        throw $msg
    }


    $packageVersion = $searchResult.version
    $packageName = $searchResult.title

    # search for package name in packages.config. If not exists, we can add it here.
    $confPackage = $packageConfig.packages.package | Where-Object { $_.id -eq $packageName } 
    if (($confPackage | Measure-Object).count -gt 1) {
        throw "Please check packages.conf. You seem to have the same package listed multiple times."
    }
    if ($null -eq $confPackage) {
        # Add the package to the file here.
        $xmlElement = $packageConfig.CreateElement("package", "http://schemas.microsoft.com/developer/msbuild/2003")
        $xmlElement.SetAttribute("id", $packageName)
        $xmlElement.SetAttribute("version", $packageVersion)
        $xmlElement.SetAttribute("targetFramework", "netnano1.0")
        $packageConfig.packages.AppendChild($xmlElement) | out-null
        $packageConfig.Save($packageConfigFilePath)
    }
    elseif ($confPackage.version -ne $packageVersion) {
        # we have the package listed in the file already. Update the version
        $confPackage.version = $packageVersion
        $packageConfig.Save($packageConfigFilePath)
    }
    else {
        write-host "packages.config file already had a proper reference to $nugetPackage!"
    }


    # Now we have the package file updated, let's see if we have the package downloaded.  
    # We'll assume that the packages folder for this solution is one level up.
    $SolutionPackagesNugetPackagePath = Join-Path  "..\packages" "$packageName.$packageVersion"

    # Do a NuGet restore based on the packages.conf file.
    set-location $projectFileObject.Directory
    Invoke-Expression ($nugetLocation + " restore -solutiondirectory .\ -outputdirectory ..\packages\")
    set-location $startLocation

    if (!(Test-Path $SolutionPackagesNugetPackagePath)) {
        throw "The package path doesn't seem to exist at $SolutionPackagesNugetPackagePath"
    }
    $PathToPackageDll = "{0}\lib\{1}.dll" -f $SolutionPackagesNugetPackagePath, $packageName

    # Sanity check to make sure the DLL exists
    if (!(test-path $PathToPackageDll)) { throw "The expected DLL was not found at $PathToPackageDll" }

    # Find the node where you want to add the new child element
    $newChildGoesInHere = $xmlNfProj.SelectSingleNode("//ns:ItemGroup[ns:Reference[contains(@Include, 'mscorlib')]]", $nsManager)
    #Look for the node we're trying to add
    $PackageReferenceNode = $newChildGoesInHere.SelectSingleNode("//*[@Include='$packageName']")
    # Check if the node is found and valid
    if ($null -eq $PackageReferenceNode) {
        # Create the new elements to add a brand new reference to this package
        $xmlReference = $xmlNfProj.CreateElement("Reference", "http://schemas.microsoft.com/developer/msbuild/2003")
        $xmlReference.SetAttribute("Include", $packageName)
    
        $xmlHintPath = $xmlNfProj.CreateElement("HintPath", "http://schemas.microsoft.com/developer/msbuild/2003")
        $xmlHintPath.InnerText = $PathToPackageDll
    
        $xmlReference.AppendChild($xmlHintPath) | Out-Null
        $newChildGoesInHere.AppendChild($xmlReference) | Out-Null

        $xmlNfProj.Save($ProjectFiles.FullName)
    }
    elseif ($PackageReferenceNode.HintPath -ne $PathToPackageDll) {
        #The reference in this file seems old. Let's update with the current dll path
        $PackageReferenceNode.HintPath = $PathToPackageDll
        $xmlNfProj.Save($projectFileObject.FullName)
    }
    else {
        write-host "Project file  $($projectFileObject.name) already had a proper reference to $nugetPackage!"
    }
    write-host "Project is updated with $nugetPackage!"    -BackgroundColor DarkBlue -ForegroundColor Yellow

}

