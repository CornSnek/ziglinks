# Ziglinks
A Command-Line Interface (CLI) version manager for the [Zig programming language](https://github.com/ziglang/zig) and also supports managing [ZLS](https://github.com/zigtools/zls). This adds symlinks to different versions for each Zig/ZLS binary you provide. To build this, Zig version of 0.13.0 is recommended.

## Purpose
I wanted to make a version manager for Zig.

One reason was due to the different versions that each Zig project would require. Some projects might use a development version such as the `master` versions in https://ziglang.org/download/. Some projects are very old and would require old versions such as `0.10.0`.

Due to each of these different Zig versions, ZLS also requires specific versions for each Zig binary in order for ZLS to work. ZLS may also need to be manually built in order to work with `master` versions. I have made this program just to try to facilitate this and archive different versions.

## Overview
This version manager reads from a file called `ziglinks.ini`.

You provide information such as download links, the folder name of the version you want to download (The folder name you provide is written in `[Each section]` in the `.ini` file). For more information of the different keys you can use, type the command `./ziglinks --keys`. You can also see the `ziglinks.ini` provided in this repository for examples.

When installing a version, it downloads the package links provided in the .ini file to the `downloads/` folder. It then extracts the zig/zls packages to the `versions/` folder. Finally, it adds symlinks to the zig/zls binaries you want to install in the `symlinks/` version.

To install a version, use `./ziglinks --install -version (version_name)`, or `./ziglinks --install -choice` to choose a section in the .ini file.

## PATH variable
In order to use the symlink binaries, you can try to edit the PATH variable for Windows/Linux/MacOS to the folder `/path/to/ziglinks/binary/symlinks/`.

## Symlink Info (Windows)
You do not necessarily require administrator privileges in order to use the program. However, for Windows, it is a requirement. There is a prompt that will say the following, for example:

```ansi
The program will try to run an elevated powershell command:

"""
start-process powershell -Verb runas -ArgumentList "cd C:\Path\To\ziglinks\binary\symlinks; new-item -ItemType SymbolicLink -Path zig.exe -Target ..\versions\Windows-0.13.0-x86_64\zig\zig-windows-x86_64-0.13.0\zig.exe; write-host;" -Wait
"""

Please allow administrator priviliges to run the command above to create the symlink 'zig.exe' to the path '..\versions\Windows-0.13.0-x86_64\zig\zig-windows-x86_64-0.13.0\zig.exe'.
Press enter to continue...
```

This simply runs `new-item -ItemType SymbolicLink -Path ... -Target ...` in order to add symlinks to Windows.