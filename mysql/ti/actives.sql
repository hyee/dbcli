/*[[Show active sessions. Usage: @@NAME [-u|-f"<filter>"] 
    -f"<filter>": Customize the `WHERE` clause
    -u          : Only list the statements for current user
    --[[--
        &filter: {
            default={command != 'Sleep'}
            f={}
            u={user() like concat(User,'@%')}
        }
    --]]--
]]*/
SELECT SUBSTRING_INDEX(INSTANCE,':',1) INSTANCE,
       ID,USER,
       SUBSTRING_INDEX(HOST,':',1) HOST,
       DB,COMMAND,
       SUBSTRING_INDEX(TxnStart,'.',1) TxnStart,
       TIME,STATE,MEM,DISK,
       concat(substr(digest,1,18),' ..') AS digest,
       substr(replace(replace(replace(replace(trim(info),'\n',' '),' ','<>'),'><',''),'<>',' '),1,150) info
FROM   information_schema.cluster_processlist
WHERE  &filter;