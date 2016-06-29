/*[[Generate SQL performance chart(dbms_sqltune.report_sql_detail). Usage: @@NAME <sql_id> [plan_hash_value]
   --[[
      @CHECK_VERSION: 11.0={1}
      &filter: default={1=1},f={}
   --]]
]]*/
set feed off verify off
var rs CLOB;
var filename varchar2;
BEGIN
    :rs :=dbms_sqltune.report_sql_detail(:V1,:V2);
    :filename:='sqld_'||:V1||'.html';
END;
/
save rs filename