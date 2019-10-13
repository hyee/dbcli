/*[[
    Show the detail of "cellcli metriccurrent". Usage: @@NAME [<keyword>]
    Refer to page https://docs.oracle.com/en/engineered-systems/exadata-database-machine/sagug/exadata-storage-server-monitoring.html#GUID-B52267F8-FAD9-4A86-9D84-81792A914C94
    This script relies on external table EXA$METRIC which is created by shell script <dbcli_home>/oracle/shell/create_exa_external_tables.sh with the oracle user
    --[[
        @check_access_obj: EXA$METRIC_VW={}
    --]]
]]*/

SELECT *
FROM   EXA$METRIC_VW
WHERE  CELLNODE || ',' || OBJECTTYPE || ',' || NAME || ',' || METRICOBJECTNAME || ',' || METRICTYPE || ',' ||
       DESCRIPTION LIKE '%&V1%'
AND    rownum <= 256;