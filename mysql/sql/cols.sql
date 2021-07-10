/*[[ Search columns based on <schema>.<table>.<column> fuzzily. Usage: @@NAME <keyword> [<schema>|-u] -r
    -u: only search the columns of current schema
    -r: <keyword> is a regular expression instead of a `LIKE` expression

  --[[
        @ARGS  : 1
        &schema: default={LIKE concat('%',TRIM('%' FROM lower(:V2)),'%') OR :V2 IS NULL} u={=database()}
        &filter: default={LIKE concat('%',TRIM('%' FROM lower(:V1)),'%')} r={regexp concat('[[:<:]]', :V1 , '[[:>:]]')}
  --]]
]]*/
col "table_catalog,Data_Type,Character_Maximum_Length,Character_Octet_Length,Numeric_Precision,Numeric_Scale,Datetime_Precision,Character_Set_Name" noprint
env headstyle initcap autohide col

SELECT * 
FROM   information_schema.columns a
WHERE  (lower(concat_ws('.',table_schema,table_name,column_name)) &filter)
AND    (lower(table_schema) &schema)
ORDER  BY table_schema,table_name,column_name;