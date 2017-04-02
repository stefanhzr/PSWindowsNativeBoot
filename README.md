# PSWindowsNativeBoot
Automated creation of Native Boot `.vhd(x)` installations, using just a Windows Setup image `.iso`.

## Features

* Create disk image `.vhd(x)`
* Automatically mount images
* Partition and format disk image
* `DISM.exe`: Apply Windows to disk image
* `compact.exe`: Compress using `/CompactOS` and `/EXE:XPRESS16K`
* `bcdboot.exe`: Add image to boot record
* Does not rely on `Hyper-V` cmdlets - no additional components required

## Example

1. Download the `Windows Setup` `.iso`.
2. Run the following code (replace paths):

```PowerShell
. .\PSWindowsNativeBoot.ps1
New-WindowsNativeBoot -Source 'D:\Downloads\Windows10_InsiderPreview_Client_x64_en-gb_15063.iso' -ImagePath 'D:\VirtualDisk\Windows_10_Build-15063_InsiderPreview.vhdx' -ImageSize 32GB
```

3. Wait until finished, then reboot.
4. Select the new boot entry.

## Parameters

| | Description |
|---|---|
| `Source` | Path to Windows Setup image `.iso` |
| `ImagePath` | Destination for the created disk image `.vhd(x)` |
| `ImageSize` | Maximum disk image size, example: `32GB` |
| `Verbose` | Print additional information about the current process |
