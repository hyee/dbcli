/*[[Show db parameters info, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[,<keyword2>...]] [instance]
When no keyword is specified then display all non-default parameters.

Sample Output:
==============
ORCL> ora param block%check                                                                                                                            
    INST_ID          NAME           SESSION_VALUE SYS_VALUE ISDEFAULT ISOPT_ENV ISSESS_MDF ISSYS_MDF  DESCRIPTION                                      
    ------- ----------------------- ------------- --------- --------- --------- ---------- --------- --------------------------------------------------
          1 db_block_checking       FALSE         <SAME>    TRUE                FALSE      IMMEDIATE header checking and data and index block checking 
          1 db_block_checksum       TYPICAL       <SAME>    TRUE                FALSE      IMMEDIATE store checksum in db blocks and check during reads
          1 log_checkpoint_interval 0             <SAME>    TRUE                FALSE      IMMEDIATE # redo blocks checkpoint threshold                

   --[[
      @ctn: 12={ISPDB_MODIFIABLE ISPDB_MDF,}, default={}
      &V2:  default={&instance}
      @check_access_param: {
            gv$system_parameter={
               (select decode(upper(a.display_value),upper(b.display_value),'<SAME>',case when length(b.display_value)>80 then regexp_replace(b.display_value,', *',','||chr(10))  else b.display_value end) 
                from   gv$system_parameter b 
                where  a.inst_id=b.inst_id 
                and    a.name=b.name
                and    rownum<2) SYS_VALUE,
            }
            default={}
      }

      @check_access_env: {
            gv$sys_optimizer_env={
               (select 'TRUE' 
                from   gv$sys_optimizer_env b 
                where  a.inst_id=b.inst_id 
                and    a.name=b.name
                and    rownum<2) ISOPT_ENV,
            }
            default={}
      }
   --]]
]]*/
set printsize 999
select inst_id,NAME,
       case when length(DISPLAY_VALUE)>80 then regexp_replace(DISPLAY_VALUE,', *',','||chr(10)) else DISPLAY_VALUE end session_value,
       &check_access_param
       isdefault,
       &check_access_env
       isses_modifiable issess_mdf,issys_modifiable issys_mdf,&CTN DESCRIPTION
from (select a.*,upper(b.instance_name) sid 
       from  gv$parameter a, gv$instance b 
       where a.inst_id=b.inst_id 
       and   a.inst_id=nvl(:V2,userenv('instance'))) a
WHERE ((
      :V1 is NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V1||'%')  OR 
      :V2 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V2||'%')  OR
      :V3 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V3||'%')  OR
      :V4 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V4||'%')  OR
      :V5 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V5||'%')) 
  OR (:V1 IS NULL and isdefault='FALSE'))
order by name