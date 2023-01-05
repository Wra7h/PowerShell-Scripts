# !!THE FIRST THING THE SCRIPT DOES IS MAKE SURE THAT $Base64SeatbeltZip ISN'T NULL SO DO THIS BEFORE ANYTHING ELSE!!
# I didn't want to just include a random string of base64

# To accomplish: 
# Step 1 Download: Go download the repo from https://github.com/GhostPack/Seatbelt
# Step 2 Encode: 
#     [convert]::ToBase64String((Get-Content -path "C:\Path\To\Seatbelt-Master.zip" -Encoding byte)) | clip 
# Step 3 Paste: Paste the contents of your clipboard as the value of the $Base64SeatbeltZip var

# Should look like:  $Base64SeatbeltZip = "<base64 string here>"
$Base64SeatbeltZip = $null

function Invoke-Retractor() 
{
    <#
    .SYNOPSIS
    Creates a .csproj that only includes the user-specified commands/group. The idea is to have a version of Seatbelt that only
    contains information the user finds valuable, which in turn a smaller executable is created. To use this function, you must
    follow the steps at the top of the Invoke-Retractor.ps1 or create a variable in your console called $Base64SeatbeltZip that
    is a base64 string of the Seatbelt-master.zip.
    
    Author: Christian W (@Wra7h)

    .DESCRIPTION
    Creates a .csproj that only includes the user-specified commands/group. The idea is to have a version of Seatbelt that only
    contains information the user finds valuable, which in turn a smaller executable is created.
    
    .PARAMETER Commands
    Specifies the commands to include. More than one may be specified as a comma-separated value: "wmi, reg,sysmon"
    
    .PARAMETER Group
    Specifies a group of commands to use. 
    
    .PARAMETER DotNetVersion
    Specifies the version of .NET Framework to use. Accepted values: '3.5', '4.7.2', or '4.8'
    
    .PARAMETER Dir
    The directory that will be used to hold the Seatbelt source code, new .csproj files, and a bin folder containing the executables.
    
    .PARAMETER MSBuild
    The path to msbuild.exe. This path should NOT be under C:\Windows\Microsoft.NET\Framework64\v3.5 or C:\Windows\Microsoft.NET\Framework64\v4.0.30319.
    Feel free to change the default, the included default value set it what was used for testing.
    [Default: "C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe"]

    .PARAMETER ShowCommands
    A switch to see what commands/groups are available for use.

    .LINK
    Seatbelt Source: https://github.com/GhostPack/Seatbelt

    .EXAMPLE
    C:\PS> Invoke-Retractor -DotNetVersion 3.5 -Commands sysmon, reg -Dir C:\users\user\Desktop\abcd\efg\hijk
    .EXAMPLE
    C:\PS> Invoke-Retractor -Group Chromium -DotNetVersion '4.7.2' -Dir C:\Windows\temp
    .EXAMPLE
    C:\PS> Invoke-Retractor -Group All -DotNetVersion 4.8 -Dir C:\Windows\temp
    #>
    [CmdletBinding()]
    param
    (
        [string[]]$Commands,
        [ValidateSet('System', 'Remote', 'User', 'Misc', 'Chromium', 'Slack', 'All')]
        [string]$Group,
        [Parameter(Mandatory=$true)]
        [ValidateSet('3.5', '4.7.2', '4.8')]
        [string]$DotNetVersion,
        [Parameter(Mandatory=$true)]
        [string]$Dir,
        [string]$MSBuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe",
        [switch]$ShowCommands

    )

    $ErrorActionPreference = 'Stop'

    if ($Base64SeatbeltZip -eq $null)
    {
        Write-Host -ForegroundColor Red "[-] ERROR: " -NoNewline
        Write-Host "'`$Base64SeatbeltZip' is null."
        Write-Host -ForegroundColor Yellow "`nOption 1: Add the Base64 string to the top of this script and reimport."
        Write-Host -ForegroundColor Yellow "Option 2: Run the following command in your console after changing the path. "
        Write-Host "Command: `$Base64SeatbeltZip = [Convert]::ToBase64String((Get-Content -path `"C:\Path\To\Seatbelt-master.zip`" -Encoding byte))"
        return;
    }

    if (!(Test-Path "$Dir\Seatbelt"))
    {
        if (!(Test-Path "$Dir"))
        {
            (New-Item $Dir -ItemType Directory | Out-Null)
        }

        [System.Convert]::FromBase64String($Base64SeatbeltZip) | Set-Content "$Dir\Seatbelt-master.zip" -Encoding Byte
        Expand-Archive -Path "$Dir\Seatbelt-master.zip" -DestinationPath "$Dir\Seatbelt" -Force
        Set-QuickFixes -Files "$Dir\Seatbelt"
    }

    if (!(Test-Path $MSBuild))
    {
        Write-Host -ForegroundColor Red "[-] ERROR: " -NoNewline
        Write-Host "Specified MSBuild does not exist. [$MSBuild]"
        return
    }

    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host " Using directory: " -NoNewline
    Write-host -ForegroundColor Yellow  $Dir

    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host " DotNet version: " -NoNewline
    Write-host -ForegroundColor Yellow  $DotNetVersion

    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host " Grabbing command details..."

    $CSFiles = (Get-ChildItem -Path "$Dir\Seatbelt\" -File "*.cs" -Recurse).FullName

    $CommandFiles = $CSFiles | Where-Object {$_ -match "\\Commands\\"}

    $CSFiles = Compare-Object $CSFiles $CommandFiles | Select-Object -Expand InputObject

    $SeatbeltCommands = Get-SeatbeltCommandData -FilePaths $CommandFiles
    
    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host -ForegroundColor Cyan " $($SeatbeltCommands.Length) " -NoNewline
    Write-Host "commands found"

    
    $SeatbeltCommands = $SeatbeltCommands | Sort-Object -Property Name
    if ($ShowCommands -or (($Commands -eq $null) -and ($Group -eq $null)))
    {
        $SeatbeltCommands | Select Name,Description,Group | Where -Property Name -ne $null
        return
    }


    #Identify the commands to add to the csproj

    $Using = @()

    if (($Commands -ne $null) -and ($Group -ne "All"))
    {
        foreach($command in $Commands)
        {
            foreach($SeatbeltCommand in $SeatbeltCommands)
            {
                if ($Command -eq $SeatbeltCommand.Name)
                {
                    $CSFiles += $SeatbeltCommand.File
                    $Using += $SeatbeltCommand.Name
                    break;
                }
            }
        }

        Write-Host -ForegroundColor Cyan "[~]" -NoNewline
        Write-Host " Adding " -NoNewline
        Write-Host -ForegroundColor Yellow $Using.Count -NoNewline
        Write-Host " specified commands"
    }


    if (![String]::IsNullOrEmpty($Group))
    {
        Write-Host -ForegroundColor Cyan "[~]" -NoNewline
        Write-Host " Adding " -NoNewline
        Write-Host -ForegroundColor Yellow $Group -NoNewline
        Write-Host " command group"

        if ($Group -eq "All")
        {
            foreach($SeatbeltCommand in $SeatbeltCommands)
            {
                $CSFiles += $SeatbeltCommand.File
                $Using += $SeatbeltCommand.Name
            }
        }
        else
        {
            foreach($SeatbeltCommand in $SeatbeltCommands)
            {
                if ($SeatbeltCommand.Group.Contains((Get-Culture).TextInfo.ToTitleCase($Group)))
                {
                    $CSFiles += $SeatbeltCommand.File
                    $Using += $SeatbeltCommand.Name
                }
            }
        }
    }

    #Filter any duplicates
    $CSFiles = $CSFiles | Sort-Object -Unique
    $Using = $Using | Sort-Object -Unique


    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host " Using " -NoNewline
    Write-Host -ForegroundColor Yellow $Using.Count -NoNewline
    Write-Host " of " -NoNewline
    Write-Host -ForegroundColor Cyan $SeatbeltCommands.Count -NoNewline
    Write-Host " Commands"

    #Create the new .csproj
    $CSProjFile = New-CSProjConfig -BasePath "$Dir\Seatbelt" -DotNetVersion $DotNetVersion -CSFilesToKeep $CSFiles


    #Build release
    $Build = (&$MSBuild $CSProjFile /property:Configuration=Release)

    if (($Build | Select-String "Build Succeeded").Matches.Count -gt 0)
    {
        
        #Build succeeded, print exe path to console
        Write-Host -ForegroundColor Green "[+] Build Succeeded: " -NoNewline
        Write-Host ($Build | Select-String -Pattern "->").ToString().Split("->")[2].Trim()

    }
    else
    {
        Write-Host -ForegroundColor Red "[-] Build Failed: " -NoNewline
        Set-Content $Dir\Error.txt -Value $Build
        Write-Host "$Dir\Error.txt"
    }
    
}

function Set-QuickFixes()
{
    param
    (
        $Files
    )

    #Sysmon fix for an unnecessary include that prevents compilation
    $Filepath = (Get-ChildItem -Path $Files -Recurse -File "SysmonCommand.cs").FullName
    $fix = Get-Content $Filepath | Select-String -Pattern "using Seatbelt.Commands.Windows;" -NotMatch
    Set-Content $Filepath -Value $fix
}

function Get-SeatbeltCommandData()
{
    param
    (
        $FilePaths
    )

    $ErrorActionPreference = ‘SilentlyContinue’

    $Commands = @()

    foreach ($File in $FilePaths)
    {
        $Contents = Get-Content $File
        $CommandName = ($Contents | Select-String -Pattern 'Command =>').ToString().Split('"')[1]

        # Check to make sure the Command name is not a duplicate. Mostly to prevent new entries for ExplicitLogonEvents Command.
        $Commands | %{if ($_.Name -eq $CommandName){
            $_.File += $file;
            continue}}


        $CommandDescription = (($Contents | Select-String -Pattern 'Description =>').ToString() | Select-String -Pattern '".*"').Matches.Value.Replace('\"',"'")
        $CommandDescription = $CommandDescription.TrimStart('"').TrimEnd('"')
        
        #Get the command groups
        $CommandGroup = @()

        foreach ($item in (($Contents | Select-String -Pattern 'Group =>').ToString().Split("//")[0] | Select-String -Pattern "CommandGroup\.[a-zA-Z]*" -AllMatches).Matches.Value)
        {
            if ($item.Split(".")[1] -notin $CommandGroup)
            {
                $CommandGroup += $item.Split(".")[1]
            }
        }

        $Commands += [PSCustomObject]@{"Name"=$CommandName; "Description"=$CommandDescription; "Group" = $CommandGroup; "File" = @($File)}
    }


    return ($Commands | ? {$_.Name -ne $null -and $_.Name -ne "Template"})
}

function Add-Interops()
{
    param
    (
        $FilesToKeep,
        $BasePath
    )

    $ErrorActionPreference = ‘SilentlyContinue’

    $Keep = $FilesToKeep | Select-String -Pattern "\\Interop\\" -NotMatch
    $AvailableInterops = $FilesToKeep | Select-String -Pattern "\\Interop\\"
    $Interops = @()

    foreach ($file in $Keep)
    {
        $FileContent = Get-Content $file

        foreach ($i in $AvailableInterops)
        {
            $interop = (Split-Path -Leaf $i).Split(".")[0]
            if (($FileContent -match "$interop") -and !($FileContent -match "$interop\.dll"))
            {
                $Interops += $i
            }

        }
    }

    if ($Interops | %{ $_ -match ".+Secur32.cs"})
    {
        $Keep += (Get-ChildItem $BasePath -File "SecBufferDesc.cs" -Recurse).FullName
        $Keep += (Get-ChildItem $BasePath -File "SecBuffer.cs" -Recurse).FullName
    }

    
    $Keep += (Get-ChildItem $BasePath -File "Win32Error.cs" -Recurse).FullName
    $Keep += (Get-ChildItem $BasePath -File "Shell32.cs" -Recurse).FullName
    $Keep += $Interops | Sort-Object -Unique

    Write-Host -ForegroundColor Cyan "[~]" -NoNewline
    Write-Host " Using " -NoNewline
    Write-Host -ForegroundColor Yellow $($Interops | Sort-Object -Unique).Count -NoNewline
    Write-Host " of " -NoNewline
    Write-Host -ForegroundColor Cyan $AvailableInterops.Count -NoNewline
    Write-Host " Interops"

    return ($Keep  | Sort-Object -Unique)
}

function New-CSProjConfig()
{
    param
    (
        $BasePath,
        $DotNetVersion,
        $CSFilesToKeep 
    )
    $Date = (Get-Date).ToUniversalTime().ToString("hhmmss")
    $CSPROJ = (Get-ChildItem -Path $BasePath -File *.csproj -Recurse | Select-Object -First 1).FullName

    $CSProjContents = Get-Content $CSPROJ

    #Set the DotNet version
    $DefaultDotNetVer = $CSProjContents | Select-String -Pattern "TargetFrameworkVersion"
    $CSProjContents = $CSProjContents.Replace($DefaultDotNetVer,"`t<TargetFrameworkVersion>v$DotNetVersion</TargetFrameworkVersion>")

    #Get full path to app.config 
    $AppConfig = $CSProjContents | Select-String -Pattern "app.config"
    $CSProjContents = $CSProjContents.Replace($AppConfig,"`t`t<None Include=`"$((Get-ChildItem $BasePath -Recurse -File `"app.config`").FullName)`"/>")

    #Set the output path
    
    $CSProjContents = $CSProjContents.Replace("    <OutputPath>bin\Release\</OutputPath>","    <OutputPath>$(Split-Path $BasePath)\bin\</OutputPath>")

    #Set AssemblyName
    $CSProjContents = $CSProjContents.Replace("    <AssemblyName>Seatbelt</AssemblyName>","<AssemblyName>Seatbelt_$Date</AssemblyName>")


    #Get the first Compile Include

    $Includes = ($CSProjContents | Select-String -Pattern "<Compile Include=")
    $FirstIncludeLine = $Includes[0].LineNumber

    $CSProjContents = ($CSProjContents | Select-String -Pattern "<Compile Include=" -NotMatch)

    $FinalCSProj = $CSProjContents[0..($FirstIncludeLine-2)]

    #Add required files that were under the "Commands" directory
    foreach($basename in $("CommandBase.cs", "CommandDTOBase.cs", "CommandGroup.cs", "CommandOutputTypeAttribute.cs", "HostDTO.cs", "ErrorDTO.cs", "VerboseDTO.cs", "WarningDTO.cs"))
    {
        $CSFilesToKeep += (Get-ChildItem $BasePath -Recurse -File $basename).FullName
    }
    
    $CSFilesToKeep = Add-Interops -FilesToKeep $CSFilesToKeep -BasePath $BasePath

    foreach($file in $CSFilesToKeep)
    {
        $AddedIncludes += "    <Compile Include=`"$file`" />`n"
    }

    $FinalCSProj += $AddedIncludes
    $FinalCSProj += $CSProjContents[($FirstIncludeLine-1)..$FirstIncludeLine]
    $FinalCSProj += $CSProjContents[($FirstIncludeLine+1)..$CSProjContents.Count]

    $Out = $("$(Split-Path $BasePath)\Seatbelt_$date.csproj")
    Set-Content $Out -Value $FinalCSProj

    Write-Host -ForegroundColor Green "[+] Wrote: " -NoNewline
    Write-Host $Out
    
    return $Out
}