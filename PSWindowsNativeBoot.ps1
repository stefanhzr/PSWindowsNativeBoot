<#
    The MIT License (MIT)

    Copyright (c) 2017 Stefan H

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>

#Requires -RunAsAdministrator

function Mount-VirtualDiskImage {
    [CmdletBinding()]

    param(
        # Location of disk image
        [Parameter(Mandatory=$true,
                   Position=1,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImagePath
    )

    # Get assigned drive letters before mount
    $mountDrives = (Get-Volume).DriveLetter

    # Mount virtual disk image
    Mount-DiskImage -ImagePath $ImagePath

    # Get and return drive letter
    (Get-Volume).DriveLetter | ForEach-Object {
        if ($mountDrives -notcontains $_) {
            return "$_" + ":"
        }
    }
}

function New-VirtualDiskImage {
    [CmdletBinding()]

    param(
        # Location of created disk image
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName="ImagePath",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImagePath,

        # Disk image size
        [Parameter(Mandatory=$true)]
        [ValidateRange(1GB, 2040GB)]
        [long]
        $Size
    )

    # Create .vhdx
    $resultDiskPart = "create vdisk file=`"$ImagePath`" type=expandable maximum=$($Size / 1MB)" | diskpart
    if (($resultDiskPart -match 'DiskPart successfully created the virtual disk file.') -like $null) {
        Write-Error "Failed to create virtual disk image, see $PSScriptRoot diskpart.log for more information."
        $resultDiskPart | Out-File "$PSScriptRoot\diskpart.log"
        break
    }

    # Mount the virtual disk image
    Mount-DiskImage -ImagePath $ImagePath -StorageType VHDX -NoDriveLetter

    # Get mounted disk images with PartitionStyle "RAW"
    $diskRAW = Get-Disk | Where-Object -FilterScript {
        $_.PartitionStyle -eq 'RAW' -and $_.FriendlyName -eq 'Msft Virtual Disk'
    }

    # Return error and break if none found
    if ($diskRAW -like $null) {
        Write-Error 'Could not find any mounted disk images with PartitionStyle "RAW".'
        break
    }

    # Suppress the "You need to format" dialog by temporarily stopping the associated service
    Stop-Service -Name ShellHWDetection

    # Initialize virtual disk, create partition and format
    $diskRAW | ForEach-Object {
        Initialize-Disk -UniqueId $_.UniqueId
        $diskPartition = New-Partition -DiskId $_.UniqueId -AssignDriveLetter -UseMaximumSize
        $diskVolume = Format-Volume -Partition $diskPartition -FileSystem NTFS
    }

    # Resume the previously stopped service
    Start-Service -Name ShellHWDetection

    # Dismount virtual disk image
    Dismount-DiskImage -ImagePath $ImagePath
}

function New-WindowsNativeBoot {
    [CmdletBinding()]

    param(
        # Windows Setup .iso location
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName="Source",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Source,

        # Destination of the .vhd(x)
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName="Source",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImagePath,

        # Partition size
        [Parameter(Mandatory=$true)]
        [ValidateRange(1GB, 2040GB)]
        [long]
        $Size,

        # Windows Setup index
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [int]
        $Index = 1
    )

    # Create disk image
    Write-Verbose '(1/6) Creating disk image'
    New-VirtualDiskImage -ImagePath $ImagePath -Size $Size

    # Mount images
    Write-Verbose '(2/6) Mounting install media and disk image'
    $mntInstall = Mount-VirtualDiskImage -ImagePath $Source
    $mntVirtualDisk = Mount-VirtualDiskImage -ImagePath $ImagePath

    # Apply Windows image to mounted disk image
    Write-Verbose '(3/6) Applying Windows to disk image'
    & Dism /Apply-Image /ImageFile:"$mntInstall\Sources\install.wim" /Index:$Index /ApplyDir:$mntVirtualDisk /Compact | Out-Null

    # Compress disk image
    Write-Verbose '(4/6) Compressing disk image'
    @(
        "$mntVirtualDisk\Program Files"
        "$mntVirtualDisk\Program Files (x86)"
        "$mntVirtualDisk\ProgramData"
        "$mntVirtualDisk\MSOCache"
        "$mntVirtualDisk\Windows\assembly"
        "$mntVirtualDisk\Windows\InfusedApps"
        "$mntVirtualDisk\Windows\Installer"
        "$mntVirtualDisk\Windows\Panther"
        "$mntVirtualDisk\Windows\SoftwareDistribution"
        "$mntVirtualDisk\Windows\System32\catroot2"
        "$mntVirtualDisk\Windows\System32\LogFiles"
    ) | ForEach-Object {
        Write-Verbose "Compressing files in $_"
        compact.exe /C "/S:$_" /I /F /EXE:XPRESS16K /Q | Out-Null
        compact.exe /C "/S:$_" /I /Q | Out-Null
    }

    # Add virtual disk to boot record
    Write-Verbose '(5/6) Adding disk image to boot record'
    bcdboot.exe $mntVirtualDisk\Windows

    # Dismount images
    Write-Verbose '(6/6) Dismounting install media and disk image'
    Dismount-DiskImage -ImagePath $ImagePath
    Dismount-DiskImage -ImagePath $Source
}
