/*[[
    Search columns based on <schema>.<table>.<column> fuzzily. Usage: @@NAME <keyword> [-r] [<schema>|-u] [-f"<filter>"] -c
    -c          : only match column name, instead of <schema>.<table>.<column> 
    -u          : only search the columns of current schema
    -r          : <keyword> is a regular expression instead of a `LIKE` expression
    -f"<filter>": Customize the other `WHERE` clause
  --[[
        @ARGS   : 1
        &schema : default={LIKE concat('%',TRIM('%' FROM lower(:V2)),'%') OR :V2::text IS NULL} u={=current_database()}
        &filter : default={lower(&field) LIKE concat('%',TRIM('%' FROM lower(:V1)),'%')} r={regexp_like(lower(&field),concat('[[:<:]]', :V1::text, '[[:>:]]'))}
        &filter1: default={1=1} f={}
        &field  : default={concat_ws('.',table_schema,table_name,column_name)} c={column_name}
  --]]
]]*/
col "table_catalog,Data_Type,Character_Maximum_Length,Character_Octet_Length,Numeric_Precision,Numeric_Scale,Datetime_Precision,Character_Set_Name" noprint
env headstyle initcap autohide col

SELECT * 
FROM   information_schema.columns a
WHERE  (&filter)
AND    (lower(table_schema) &schema)
AND    (&filter1)
ORDER  BY table_schema,table_name,column_name;