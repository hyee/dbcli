/*[[Show TiDB variable info. Usage: @@MAME <keyword>]]*/

ENV COLWRAP 80
select * from information_schema.variables_info
where :V1 IS NOT NULL AND lower(concat(VARIABLE_NAME,',',CURRENT_VALUE)) LIKE lower('%&V1%') AND 
      (lower('&V1')!='tidb_config' AND VARIABLE_NAME!='tidb_config' or lower('&V1')='tidb_config' AND VARIABLE_NAME='tidb_config')
OR    :V1 IS NULL AND DEFAULT_VALUE!=CURRENT_VALUE and VARIABLE_NAME!='tidb_config'
ORDER  BY VARIABLE_NAME;