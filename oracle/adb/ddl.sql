/*[[
    View CREATE EXTERNAL statement of file. Usage: @@NAME {[<credential>] <URL>} | {<directory> <file>} {[<based_table>] [csv|json|xml|avro|orc|parquet|dmp]}
    Same to 'adb list [<credential>] <URL> -ddl [<based_table>]'
    Type 'adb list' for more information of the parameters

    <based_table>: The table name that has the same column list with target file.

    Examples in case of credential and bucket is predefined by 'set' command:
        @@NAME /1.csv OBJ1 csv
        @@NAME DATA_PUMP_DIR 1.json OBJ1

    --[[
        @ARGS: 1
    --]]
]]*/
adb list -ddl "&V1" "&V2" "&V3" "&V4"