/*[[
    Export the data of a query into Cloud Object Storage. Usage: @@NAME [<credential>] <URL> [-csv|-json|-xml|-dmp|-parquet] [-gzip] <query>
    Same to 'adb list [<credential>] <query> -unload'
    
    File extentions:
        -csv : export in CSV format
        -json: export in JSON format (default)
        -xml : export in XML format
        -dmp : export in Oracle Data Pump format
    Compression:
        -gzip: export the data in specific format and compress as gzip file

    Type 'adb list' for more information of the parameters
    --[[
        @ARGS: 2
    --]]
]]*/
adb list -unload "&V1" "&V2" "&V3" "&V4" "&V5"