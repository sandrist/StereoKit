param(
    [switch]$upload = $false,
    [switch]$fast = $false,
    [string]$key = ''
)

function Get-LineNumber { return $MyInvocation.ScriptLineNumber }
function Get-ScriptName { return $MyInvocation.ScriptName }

# Get the Visual Studio executable for building
$vsWhere        = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vsVersionRange = '[16.0,18.0)'
$vsExe          = & $vsWhere -latest -property productPath -version $vsVersionRange
if (!$vsExe) {
    Write-Host "$(Get-ScriptName)($(Get-LineNumber),0): error: Valid Visual Studio version not found!" -ForegroundColor red
    exit 
}
$vsExe = [io.path]::ChangeExtension($vsExe, '.com')

###########################################
## Functions                             ##
###########################################

function Replace-In-File {
    param($file, $text, $with)

    ((Get-Content -path $file) -replace $text,$with) | Set-Content -path $file
}

###########################################

function Build {
    param([parameter(Mandatory)][string] $mode, [parameter(Mandatory)][string] $project)
    & $vsExe 'StereoKit.sln' '/Build' $mode '/Project' $project | Write-Host
    return $LASTEXITCODE
}

###########################################

function Test {
    & $vsExe 'StereoKit.sln' '/Build' 'Release|X64' '/Project' 'StereoKitDocumenter' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return $LASTEXITCODE
    }
    Push-Location -Path 'Tools/StereoKitDocumenter/bin/Release/net6.0/'
    & '.\StereoKitDocumenter.exe' | Write-Host
    Pop-Location
    return $LASTEXITCODE
}

###########################################

function Get-Key {
    if ($key -ne '') {
        Set-Content -path '.nugetkey' -value $key.Trim()
    } elseif (Test-Path '.nugetkey') {
        $key = Get-Content -path '.nugetkey' -Raw
    } else {
        $key = Read-Host "Please enter the NuGet API key, or n to cancel"
        if ($key -eq 'n') {
            $key = ''
        } else {
            Set-Content -path '.nugetkey' -value $key.Trim()
        }
    }
    return $key.Trim()
}

###########################################

function Build-Sizes {
    $size_x64        = (Get-Item "bin/distribute/bin/Win32/x64/Release/StereoKitC.dll").length
    $size_x64_uwp    = (Get-Item "bin/distribute/bin/UWP/x64/Release/StereoKitC.dll").length
    $size_arm64_uwp  = (Get-Item "bin/distribute/bin/UWP/ARM64/Release/StereoKitC.dll").length
    $size_arm_uwp    = (Get-Item "bin/distribute/bin/UWP/ARM/Release/StereoKitC.dll").length

    $text = (@"
## Build Sizes:

| Platform | Arch  | Size, kb | Size, bytes |
| -------- | ----- | -------- | ----------- |
| Win32    | x64   | {0,8:N0} | {1,11:N0} |
| UWP      | x64   | {2,8:N0} | {3,11:N0} |
| UWP      | ARM64 | {4,8:N0} | {5,11:N0} |
| UWP      | ARM   | {6,8:N0} | {7,11:N0} |
"@ -f ([math]::Round($size_x64        /1kb), $size_x64,
       [math]::Round($size_x64_uwp    /1kb), $size_x64_uwp,
       [math]::Round($size_arm64_uwp  /1kb), $size_arm64_uwp,
       [math]::Round($size_arm_uwp    /1kb), $size_arm_uwp
       ))

    return $text
}

###########################################
## Main                                  ##
###########################################

# Notify about our upload flag status 
if ($fast -eq $true -and $upload -eq $true) {
    Write-Host "Let's not upload a fast build, just in case! Try again without the fast flag :)" -ForegroundColor yellow
    exit
}
Write-Host 'Building... ' -NoNewline
if ($upload -eq $false) {
    Write-Host 'local only.' -ForegroundColor White
} else {
    Write-Host 'AND UPLOADING!' -ForegroundColor Green
}
if ($fast -eq $true) {
    Write-Host 'Making a "fast" build, incremental build issues may be present.'
}

# Switch to the right folder

Push-Location -Path "$PSScriptRoot\.."

#### Update Version #######################

# Print version, so we know we're building the right version right away
$fileData = Get-Content -path 'StereoKitC\stereokit.h' -Raw;
$fileData -match '#define SK_VERSION_MAJOR\s+(?<ver>\d+)' | Out-Null
$major = $Matches.ver
$fileData -match '#define SK_VERSION_MINOR\s+(?<ver>\d+)' | Out-Null
$minor = $Matches.ver
$fileData -match '#define SK_VERSION_PATCH\s+(?<ver>\d+)' | Out-Null
$patch = $Matches.ver
$fileData -match '#define SK_VERSION_PRERELEASE\s+(?<ver>\d+)' | Out-Null
$pre = $Matches.ver

$version = "$major.$minor.$patch"
if ($pre -ne 0) {
    $version = "$version-preview.$pre"
}

# Notify of build, and output the version
Write-Host @"
   _____ _                      _  ___ _   
  / ____| |                    | |/ (_) |  
 | (___ | |_ ___ _ __ ___  ___ | ' / _| |_ 
  \___ \| __/ _ \ '__/ _ \/ _ \|  < | | __|
  ____) | ||  __/ | |  __/ (_) | . \| | |_ 
 |_____/ \__\___|_|  \___|\___/|_|\_\_|\__| 
"@ -NoNewline -ForegroundColor White
Write-Host "v$version`n" -ForegroundColor Cyan

# Ensure the version string for the package matches the StereoKit version
Replace-In-File -file 'StereoKit\StereoKit.csproj' -text '<Version>(.*)</Version>' -with "<Version>$version</Version>"
Replace-In-File -file 'xmake.lua' -text 'set_version(.*)' -with "set_version(`"$version`")"
Replace-In-File -file 'CMakeLists.txt' -text 'StereoKit VERSION "(.*)"' -with "StereoKit VERSION `"$major.$minor.$patch`""

#### Clean Project ########################

# Clean out the old files, do a full build
if (Test-Path 'bin\distribute') {
    Remove-Item 'bin\distribute' -Recurse
}
Write-Host 'Cleaning old files...'
if ($fast -eq $false) {
    & $vsExe 'StereoKit.sln' '/Clean' 'Release|X64' | Out-Null
    Write-Host '..cleaned Release x64'
    & $vsExe 'StereoKit.sln' '/Clean' 'Release|ARM64' | Out-Null
    Write-Host '..cleaned Release ARM64'
    & $vsExe 'StereoKit.sln' '/Clean' 'Release|ARM' | Out-Null
    Write-Host '..cleaned Release ARM'
}
Write-Host 'Cleaned'

#### Build Windows ########################

Write-Host @"

__      ___         _               
\ \    / (_)_ _  __| |_____ __ _____
 \ \/\/ /| | ' \/ _' / _ \ V  V (_-<
  \_/\_/ |_|_||_\__,_\___/\_/\_//__/

"@ -ForegroundColor White

# Platform specific shader compile for shaders bundled in the platform binary!
Write-Host "--- Compiling shaders as Windows only ---" -ForegroundColor green
& 'Tools/skshaderc.exe' '-O3' '-h' '-f' '-t' 'x' '-i' 'Tools/include' 'StereoKitC/shaders_builtin/*.hlsl' | Out-Null

# Build Win32 first
Write-Host "--- Beginning build: Win32 x64 ---" -ForegroundColor green
$result = Build -mode "Release|X64" -project "StereoKitC"
if ($result -ne 0) {
    Write-Host '--- Win32 x64 build failed! Stopping build! ---' -ForegroundColor red
    Pop-Location
    exit
}
Write-Host "--- Finished building: Win32 x64 ---" -ForegroundColor green
#Write-Host "--- Beginning build: Win32 ARM64 ---" -ForegroundColor green
#$result = Build -mode "Release|ARM64" -project "StereoKitC"
#if ($result -ne 0) {
#    Write-Host '--- Win32 ARM64 build failed! Stopping build! ---' -ForegroundColor red
#    exit
#}
#Write-Host "--- Finished building: Win32 ARM64 ---" -ForegroundColor green

# Build UWP next
Write-Host "--- Beginning build: UWP x64 ---" -ForegroundColor green
$result = Build -mode "Release|X64" -project "StereoKitC_UWP"
if ($result -ne 0) {
    Write-Host '--- UWP x64 build failed! Stopping build! ---' -ForegroundColor red
    Pop-Location
    exit
}
Write-Host "--- Finished building: UWP x64 ---" -ForegroundColor green
Write-Host "--- Beginning build: UWP ARM64 ---" -ForegroundColor green
$result = Build -mode "Release|ARM64" -project "StereoKitC_UWP"
if ($result -ne 0) {
    Write-Host '--- UWP ARM64 build failed! Stopping build! ---' -ForegroundColor red
    Pop-Location
    exit
}
Write-Host "--- Finished building: UWP ARM64 ---" -ForegroundColor green
Write-Host "--- Beginning build: UWP ARM ---" -ForegroundColor green
$result = Build -mode "Release|ARM" -project "StereoKitC_UWP"
if ($result -ne 0) {
    Write-Host '--- UWP ARM build failed! Stopping build! ---' -ForegroundColor red
    Pop-Location
    exit
}
Write-Host "--- Finished building: UWP ARM ---" -ForegroundColor green

#### Execute Windows Tests ########################

# Run tests!
if ($fast -eq $false) {
    Write-Host "`nRunning Windows Tests!"
    if ( Test -ne 0 ) {
        Write-Host '--- Tests failed! Stopping build! ---' -ForegroundColor red
        Pop-Location
        exit
    }
    Write-Host 'Tests passed!' -ForegroundColor green
} else {
    Write-Host "`nSkipping tests for fast build!" -ForegroundColor yellow
}

#### Assemble NuGet Package ###############

Write-Host @"

  _  _       ___     _   
 | \| |_  _ / __|___| |_ 
 | .' | || | (_ / -_)  _|
 |_|\_|\_,_|\___\___|\__|
                      
"@ -ForegroundColor White

Write-Host "--- Beginning build: NuGet package ---" -ForegroundColor green
# Turn on NuGet package generation, build, then turn it off again
$packageOff = '<GeneratePackageOnBuild>false</GeneratePackageOnBuild>'
$packageOn  = '<GeneratePackageOnBuild>true</GeneratePackageOnBuild>'
Replace-In-File -file 'StereoKit\StereoKit.csproj' -text $packageOff -with $packageOn
$result = Build -mode "Release|Any CPU" -project "StereoKit"
Replace-In-File -file 'StereoKit\StereoKit.csproj' -text $packageOn -with $packageOff
if ($result -ne 0) {
    Write-Host '--- NuGet build failed! Stopping build! ---' -ForegroundColor red
    Pop-Location
    exit
}
Write-Host "--- Finished building: NuGet package ---"-ForegroundColor green

#### Create Build Info File ###############

$build_size = Build-Sizes
$build_info = "# StereoKit v$version Build Information

$build_size"
Set-Content -path 'Tools\BuildInfo.md' -value $build_info
Write-Host $build_info

#### Upload NuGet Package #################

if ($upload) {
    $key = Get-Key
    if ($key -ne '') {
        & dotnet nuget push "bin\StereoKit.$version.nupkg" -k $key -s https://api.nuget.org/v3/index.json
    } else {
        Write-Host 'No key, cancelling upload'
    }
}

# Put the shaders back to cross-platform to make dev a little nicer!
Write-Host "--- Restoring shaders to portable format for dev ---" -ForegroundColor green
& 'Tools/skshaderc.exe' '-O3' '-h' '-f' '-t' 'xge' '-i' 'Tools/include' 'StereoKitC/shaders_builtin/*.hlsl' | Out-Null

Write-Host "Done!" -ForegroundColor green

Pop-Location