/*[[
    View top lines of file in Object Storage. Usage: @@NAME {[<credential>] <URL>} | {<directory> <file>} {[<based_table>] [csv|json|xml|avro|orc|parquet]}
    Same to 'adb list [<credential>] <URL> -view [<based_table>]'
    Type 'adb list' for more information of the parameters

    <based_table>: The table name that has the same column list with target file.

    Examples in case of credential and bucket is predefined by 'set' command:
        @@NAME /1.csv
        @@NAME /1.csv OBJ1 csv
        @@NAME DATA_PUMP_DIR 1.json

    --[[
        @ARGS: 1
    --]]
]]*/
adb list -view "&V1" "&V2" "&V3" "&V4"