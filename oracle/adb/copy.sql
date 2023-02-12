/*[[
    Copy files between Object Storage and Oracle directory. Usage: @@NAME [<credential>] {<directory>|<URL>} {<URL>|<directory>} <keyword>
    Details:
        1) @@NAME [<credential>] {<source directory>|<source URL>} {<target URL>|<target directory>} <keyword>
        2) @@NAME [<credential>] <source URL> <target URL> <keyword>
        3) @@NAME [<credential>] <source URL> <target file URL> <source File name>
        4) @@NAME <directory>  <target file name> <source file name>
        5) @@NAME <directory1> <directory2>  <keyword>

    Type 'adb list' for more information of the parameters
    --[[
        @ARGS: 2
    --]]
]]*/
adb list -copy "&V1" "&V2" "&v3" "&v4"