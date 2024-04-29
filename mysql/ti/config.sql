/*[[Search cluster config/hardware/load/os with specific keyword. Usage: @@NAME <keyword> [-f"<filter>"]
    Relative views: cluster_systeminfo/cluster_config
    --[[
        &filter: default={1=1} f={}
    --]]
]]*/
col value for K
SELECT * FROM (
    SELECT TYPE,INSTANCE,'Config' Source,`KEY` name,VALUE
    FROM   information_schema.cluster_config
    WHERE lower(concat(`type`,',',`instance`,',','Config',',',`key`,',',value)) LIKE lower('%&V1%')
    UNION ALL
    SELECT TYPE,INSTANCE,concat('OS -> ',system_type,'/',system_name) Source,name,VALUE
    FROM   information_schema.cluster_systeminfo
    WHERE lower(concat(`type`,',',`instance`,',','OS -> ',system_name,',',name,',',value)) LIKE lower('%&V1%')
    UNION ALL
    SELECT TYPE,INSTANCE,concat('Hardware -> ',device_type,'/',device_name) Source,name,VALUE
    FROM   information_schema.cluster_hardware
    WHERE lower(concat(`type`,',',`instance`,',','Hardware -> ',device_type,'/',device_name,',',name,',',value)) LIKE lower('%&V1%')
    UNION ALL
    SELECT TYPE,INSTANCE,concat('Load -> ',device_type,'/',device_name) Source,name,VALUE
    FROM   information_schema.cluster_load
    WHERE lower(concat(`type`,',',`instance`,',','Load -> ',device_type,'/',device_name,',',name,',',value)) LIKE lower('%&V1%')
) 
WHERE &filter
ORDER BY name,source,2,3 limit 300;