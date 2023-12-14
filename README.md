# nanoFrameworkPackageManager
PowerShell functions to manage NuGet packages for nanoFramework projects.

Use the function ``Add-NanoNugetPackage`` to add a new package to a .Net nanoFramework project. 
The script will:
- Verify the nfProj file is a nanoFramework project.
- Check nuget online for the latest version.
- Check the ``packages.config`` file for the package. It will be added or updated if it isn't included or the version is different.
- Nuget will be called to restore packages from the ``packages.config`` file.
- The nfProj file will be updated to import a reference to the DLL from the nuget package.

<b>To start, run the powershell file to load the function into memory. </b>

### Example:

```PowerShell
# add the package nanoFramework.Hardware.Esp32 to the project in the 
# current folder. Only one nfProj file is supported.
Add-NanoNugetPackage -nugetPackage "nanoFramework.Hardware.Esp32"
```

```PowerShell
# add the package nanoFramework.Hardware.Esp32 to a project in 
# another folder. Path can be relative
Add-NanoNugetPackage -nugetPackage "nanoFramework.Hardware.Esp32" -projectFile "path/to/project.nfProj"
```

```PowerShell
# add the package nanoFramework.Hardware.Esp32 to a project in 
# another folder. Specify the location of nuget.exe if it is 
# not in the path.
Add-NanoNugetPackage -nugetPackage "nanoFramework.Hardware.Esp32" -nugetLocation "c:\nuget\nuget.exe"
```

Note: ``Nuget.exe`` is required for this function to work.
