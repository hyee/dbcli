/*[[Show db parameters info, pls use 'set instance' to show the specific instance. Usage: @@NAME [<keyword1>[,<keyword2>...]] [instance] [-d]
When no keyword is specified then display all non-default parameters.
-d: query dba_hist_parameter instead of gv$parameter

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
      &d: default={1} d={0}
   --]]
]]*/
set printsize 999
set verify off feed off
var c refcursor;
declare
    v_dbid int:=:dbid;
begin
    if :d=1 then
        open :c for
            select inst_id,NAME,
                   case when length(DISPLAY_VALUE)>80 then regexp_replace(DISPLAY_VALUE,', *',','||chr(10)) else DISPLAY_VALUE end session_value,
                   &check_access_param
                   isdefault,
                   &check_access_env
                   isses_modifiable issess_mdf,issys_modifiable issys_mdf,&CTN DESCRIPTION
            from (select a.*,upper(b.instance_name) sid 
                   from  gv$parameter a, gv$instance b 
                   where a.inst_id=b.inst_id 
                   and   a.inst_id=nvl(regexp_substr(:V2,'^\d+$'),userenv('instance'))) a
            WHERE ((
                  :V1 is NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V1||'%')  OR 
                  :V2 IS NOT NULL and regexp_substr(:V2,'^\d+$') IS NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V2||'%')  OR
                  :V3 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V3||'%')  OR
                  :V4 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V4||'%')  OR
                  :V5 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V5||'%')) 
              OR (:V1 IS NULL and isdefault='FALSE'))
            order by name;
    else
        if v_dbid is null then
            select dbid into v_dbid from v$database;
        end if;
        open :c for
            with params as(
                select lpad(decode(count(1),1,''||max(inst_id),'*'),4) inst,
                       name,
                       max(begin_value) begin_value,
                       nvl(nullif(value,max(begin_value)),'<SAME>') end_value,
                       min(isdefault) isdefault,
                       min(ismodified) ismodified
                from (
                    select instance_number inst_id,
                           parameter_name name,
                           trim(max(value) keep(dense_rank first order by snap_id)) begin_value,
                           trim(max(value) keep(dense_rank last order by snap_id)) value,
                           max(isdefault)  keep(dense_rank last order by snap_id) isdefault,
                           max(ismodified) keep(dense_rank last order by snap_id) ismodified
                    from   dba_hist_parameter
                    where  dbid=v_dbid
                    and    instance_number=nvl(regexp_substr(:V2,'^\d+$'),instance_number)
                    group  by instance_number,parameter_name)
                group by name,value)
            select a.inst,
                   name,
                   begin_value,
                   end_value,
                   a.isdefault,
                   a.ismodified,
                   b.description
            from params a 
            left join v$parameter b using(name)
            where ((
                  :V1 is NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V1||'%')  OR 
                  :V2 IS NOT NULL and regexp_substr(:V2,'^\d+$') IS NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V2||'%')  OR
                  :V3 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V3||'%')  OR
                  :V4 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V4||'%')  OR
                  :V5 IS NOT NULL and lower(NAME||' '||DESCRIPTION) LIKE LOWER('%'||:V5||'%')) 
              OR (:V1 IS NULL and a.isdefault='FALSE'))
            order by name,inst;
    end if;
end;
/
set feed back
print c