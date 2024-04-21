/*[[Show running queries. Usage: @@NAME ["<filter>"]
    --[[--
        &V1: default={id!=CONNECTION_ID() AND command='Query'} f={}
    --]]--
]]*/
col time for smhd2
select id,user,db,time,state,replace(replace(substring(info,1,200),'\n',' '),'\r','') as short_sql 
from `performance_schema`.`processlist`
WHERE &V1