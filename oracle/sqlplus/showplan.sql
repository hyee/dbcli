-- ################################################################################
-- #
-- #          name: showplan.sql v1.0
-- #
-- #          File: showplan.sql
-- #   Description: Show SQL Plan and performance details
-- #         Usage: @showplan <SQL_ID> [Plan Hash Value] [Details: [+](B)inds|SQL (T)ext|(Pee(K)ed Binds|(P)lan|(O)utlines|Pre(D)icate|Plan (L)oading|(W)ait events|(S)tatistics]
-- #       Created: 2014-03-12
-- #        Author: Wei Huang
-- #      Web Site: www.HelloDBA.com
-- #Latest Version: http://www.HelloDBA.com/download/showplan.zip
-- #   User run as: dba
-- #     Tested DB: 11gR2
-- #    Parameters: 1: SQL_ID of SQL to be shown
-- #    Parameters: 2: Plan Hash Value, if null (Default), will show all plans
-- #    Parameters: 3: Details to be shown: [+](B)inds|SQL (T)ext|(Pee(K)ed Binds|(P)lan|(O)utlines|Pre(D)icate|Plan (L)oading|(W)ait events|(S)tatistics, 
-- #                   default is BPDTLWS; + stand for the default options
-- #
-- #  Copyright (c) 2014 Wei Huang
-- #
-- # History
-- # Modified by   When      Why
-- # -----------   -------   ----------------------------------------------------
-- ################################################################################
set autot off verify off feedback off pagesize 50000 lines 2000 long 10000000 longchunksize 10000000 serveroutput on size unlimited format wrapped buffer 99999999 head off
set termout off
col p1 noprint
col p2 new_value 2 noprint
col p3 new_value 3 noprint
select null p2, null p3 from dual where 1=2;
select nvl(upper(decode(upper('&2'),'NULL',null,upper('&2'))),null) p2, nvl(upper(decode(upper('&3'),'NULL','BPDTLWS',upper('&3'))),'BPDTLWS')||decode(instr('&3','+'),0,'','BPDTLWS') p3 from dual;
set termout on
clear columns
col xxx format a2000

prompt Usage: @showplan <SQL_ID> [Plan Hash Value] [Details: [+](B)inds|SQL (T)ext|(Pee(K)ed Binds|(P)lan|(O)utlines|Pre(D)icate|Plan (L)oading|(W)ait events|(S)tatistics]
prompt Description: Show SQL Plan
prompt 

set termout off
var sqlid varchar2(32);
var planHashValue varchar2(32);
var showOptions varchar2(32);
begin select '&1', decode(upper('&2'),'NULL',null,'&2'), nvl(upper(decode(upper('&3'),'NULL','BPDTLWS',upper('&3'))),'BPDTLWS')||decode(instr('&3','+'),0,'','BPDTLWS') into :sqlid, :planHashValue, :showOptions from dual; end;
/
set termout on

with q as (select /*+materialize*/*
           from (select sql_fulltext from v$sqlarea where sql_id=:sqlid
                 union all
                 select sql_text from dba_hist_sqltext
                 where sql_id=:sqlid and not exists (select 1 from v$sqlarea where sql_id=:sqlid))),
     p as (select /*+materialize*/*
           from (select m.SQL_ID,SQL_PLAN_HASH_VALUE PLAN_HASH_VALUE,PLAN_LINE_ID ID,PLAN_PARENT_ID PARENT_ID,
                        PLAN_OPERATION OPERATION,p.OTHER_TAG,PLAN_OPTIONS OPTIONS,PLAN_OBJECT_NAME OBJECT_NAME,
                        PLAN_OBJECT_TYPE OBJECT_TYPE,p.OPTIMIZER,PLAN_COST COST,OUTPUT_ROWS||' rows' CARDINALITY,
                        PHYSICAL_READ_BYTES+PHYSICAL_WRITE_BYTES||'/'||PLAN_BYTES BYTES,
                        p.access_predicates, p.filter_predicates, p.parsing_schema_name
                 from v$sql_plan_monitor m, (select p.SQL_ID, p.PLAN_HASH_VALUE, p.ID, p.CHILD_ADDRESS, p.OTHER_TAG, 
                                                    p.OPTIMIZER, p.access_predicates, p.filter_predicates, q.parsing_schema_name 
                                             from v$sql_plan p, v$sql q
                                             where p.SQL_ID=:sqlid AND (:planHashValue is NULL or p.PLAN_HASH_VALUE=to_number(:planHashValue))
                                             and p.sql_id=q.sql_id(+) and p.CHILD_ADDRESS=q.CHILD_ADDRESS(+)
                                             union
                                             select p.SQL_ID, p.PLAN_HASH_VALUE, ID, null CHILD_ADDRESS, p.OTHER_TAG, 
                                                    p.OPTIMIZER, access_predicates, p.filter_predicates, q.parsing_schema_name 
                                             from dba_hist_sql_plan p, dba_hist_sqlstat q
                                             where p.SQL_ID=:sqlid AND (:planHashValue is NULL or p.PLAN_HASH_VALUE=to_number(:planHashValue))
                                             and p.sql_id=q.sql_id(+) and p.PLAN_HASH_VALUE=q.PLAN_HASH_VALUE(+)
                                             and not exists (select 1 from V$SQL_PLAN p1 
                                                             where p1.SQL_ID=:sqlid AND (:planHashValue is NULL or p1.PLAN_HASH_VALUE=to_number(:planHashValue)))) p
                 where m.SQL_ID=:sqlid AND (:planHashValue is NULL or m.SQL_PLAN_HASH_VALUE=to_number(:planHashValue))
                   and last_refresh_time = (select max(last_refresh_time) from v$sql_plan_monitor m
                                             where m.SQL_ID=:sqlid AND (:planHashValue is NULL or m.SQL_PLAN_HASH_VALUE=to_number(:planHashValue)))
                   and m.SQL_ID=p.SQL_ID(+) and m.SQL_PLAN_HASH_VALUE=p.PLAN_HASH_VALUE(+) and m.PLAN_LINE_ID=p.ID(+) and m.SQL_CHILD_ADDRESS=p.CHILD_ADDRESS(+)
                 union
                 select p.SQL_ID,p.PLAN_HASH_VALUE, p.ID, p.PARENT_ID,p.OPERATION,p.OTHER_TAG,p.OPTIONS,p.OBJECT_NAME,
                        p.OBJECT_TYPE, p.OPTIMIZER,p.COST,''||p.CARDINALITY CARDINALITY,''||p.BYTES BYTES,
                        p.access_predicates, p.filter_predicates, q.parsing_schema_name
                 from V$SQL_PLAN p, v$sql q
                 where p.SQL_ID=:sqlid AND (:planHashValue is NULL or p.PLAN_HASH_VALUE=to_number(:planHashValue))
                 and p.child_number = (select max(child_number) from V$SQL_PLAN p1
                                       where p1.SQL_ID=:sqlid AND (:planHashValue is NULL or p1.PLAN_HASH_VALUE=to_number(:planHashValue)))
                 and not exists (select 1 from v$sql_plan_monitor m
                                  where m.SQL_ID=:sqlid AND (:planHashValue is NULL or m.SQL_PLAN_HASH_VALUE=to_number(:planHashValue)))
                 and p.sql_id=q.sql_id(+) and p.CHILD_ADDRESS=q.CHILD_ADDRESS(+)
                 union 
                 select p.SQL_ID,p.PLAN_HASH_VALUE, p.ID, p.PARENT_ID,p.OPERATION,p.OTHER_TAG,p.OPTIONS,p.OBJECT_NAME,
                        p.OBJECT_TYPE,p.OPTIMIZER,p.COST,''||p.CARDINALITY CARDINALITY,''||p.BYTES BYTES,
                        p.access_predicates, p.filter_predicates, q.parsing_schema_name
                 from dba_hist_sql_plan p, dba_hist_sqlstat q
                 where p.SQL_ID=:sqlid AND (:planHashValue is NULL or p.PLAN_HASH_VALUE=to_number(:planHashValue))
                 and timestamp = (select max(timestamp) from dba_hist_sql_plan p1
                                  where p1.SQL_ID=:sqlid AND (:planHashValue is NULL or p1.PLAN_HASH_VALUE=to_number(:planHashValue)))
                 and not exists (select 1 from v$sql_plan_monitor  m
                                  where m.SQL_ID=:sqlid AND (:planHashValue is NULL or m.SQL_PLAN_HASH_VALUE=to_number(:planHashValue)))
                 and not exists (select 1 from V$SQL_PLAN p1
                                  where p1.SQL_ID=:sqlid AND (:planHashValue is NULL or p1.PLAN_HASH_VALUE=to_number(:planHashValue)))
                 and p.sql_id=q.sql_id(+) and p.PLAN_HASH_VALUE=q.PLAN_HASH_VALUE(+))),
     pa as ( select /*+materialize*/sql_plan_hash_value plan_hash_value, sql_plan_line_id, 
                    sql_plan_operation||' '||nvl(sql_plan_options,'') sql_plan_op,nvl(event, 'ON CPU') event, 
                    TEMP_SPACE_ALLOCATED, PGA_ALLOCATED, current_obj#, count(*) over () total_waits
               from v$active_session_history 
              where sql_plan_line_id is not null and sql_id=:sqlid AND (:planHashValue is NULL or SQL_PLAN_HASH_VALUE=to_number(:planHashValue))
              union all
             select sql_plan_hash_value plan_hash_value, sql_plan_line_id, 
                    sql_plan_operation||' '||nvl(sql_plan_options,'') sql_plan_op,nvl(event, 'ON CPU') event, 
                    TEMP_SPACE_ALLOCATED, PGA_ALLOCATED, current_obj#, count(*) over () total_waits
               from dba_hist_active_sess_history 
              where not exists (select 1 from v$active_session_history 
                                 where sql_id=:sqlid AND (:planHashValue is NULL or SQL_PLAN_HASH_VALUE=to_number(:planHashValue)))
                and sql_plan_line_id is not null and sql_id=:sqlid AND (:planHashValue is NULL or SQL_PLAN_HASH_VALUE=to_number(:planHashValue))),
     pl as ( select plan_hash_value, sql_plan_line_id, sql_plan_op, total_waits, count(*) waits
               from pa
              group by plan_hash_value, sql_plan_line_id, sql_plan_op, total_waits),
     we as (select pa.plan_hash_value, pa.event, o.owner||'.'||o.object_name||'('||o.object_type||')' wait_object, 
                   count(*) waits, total_waits from pa, dba_objects o
             where pa.current_obj#=o.object_id
             group by pa.plan_hash_value, pa.event, o.owner, o.object_name, o.object_type, total_waits),
     pb as (select /*+inline*/plan_hash_value,b.name,b.value,
                  decode(b.type#, 
                       1, 'VARCHAR2('||b.maxlength||')',
                       2, decode(b.scale, null,
                                 decode(b.precision#, null, 'NUMBER', 'FLOAT'),
                                 'NUMBER'),
                       8, 'LONG',
                       9, 'VARCHAR('||b.maxlength||')',
                       12, 'DATE',
                       23, 'RAW', 24, 'LONG RAW',
                       69, 'ROWID',
                       96, 'CHAR('||b.maxlength||')',
                       100, 'BINARY_FLOAT',
                       101, 'BINARY_DOUBLE',
                       105, 'MLSLABEL',
                       106, 'MLSLABEL',
                       112, 'CLOB',
                       113, 'BLOB', 114, 'BFILE', 115, 'CFILE',
                       178, 'TIME(' ||b.scale|| ')',
                       179, 'TIME(' ||b.scale|| ')' || ' WITH TIME ZONE',
                       180, 'TIMESTAMP(' ||b.scale|| ')',
                       181, 'TIMESTAMP(' ||b.scale|| ')' || ' WITH TIME ZONE',
                       231, 'TIMESTAMP(' ||b.scale|| ')' || ' WITH LOCAL TIME ZONE',
                       182, 'INTERVAL YEAR(' ||b.precision#||') TO MONTH',
                       183, 'INTERVAL DAY(' ||b.precision#||') TO SECOND(' ||
                             b.scale || ')',
                       208, 'UROWID',
                       'UNDEFINED') data_type
              from v$sql_plan m, xmltable('/*/peeked_binds/bind' passing xmltype(m.OTHER_XML)
                                 columns name varchar2(4000) path '/bind/@nam', 
                                         type# varchar2(4000) path '/bind/@dty',
                                         precision# varchar2(4000) path '/bind/@pre',
                                         scale varchar2(4000) path '/bind/@scl',
                                         maxlength varchar2(4000) path '/bind/@mxl',
                                         value varchar2(4000) path '/bind') b
             where m.sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue))
               and trim(OTHER_XML) is not null),
     mb as (select /*+inline*/m.sid,m.session_serial#,sql_id,b.name,b.data_type,b.value
            from V$SQL_MONITOR m, xmltable('/binds/bind' passing xmltype(m.BINDS_XML)
                                           columns name varchar2(30) path '/bind/@name', 
                                                   data_type varchar2(30) path '/bind/@dtystr', 
                                                   value varchar2(4000) path '/bind') b
           where m.sql_id = :sqlid
             and exists (select 1 from V$SQL_MONITOR m1 
                          where m1.sid=m.sid and m1.session_serial#=m.session_serial# and m1.sql_id=m.sql_id
                           and (not exists (select 1 from v$sql_plan 
                                            where sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue)))
                                or exists (select 1 from v$sql_plan p 
                                           where sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue))
                                             and m1.sql_child_address=p.child_address))
                          group by sid,session_serial#,sql_id 
                         having max(m1.last_refresh_time)=m.last_refresh_time)
             and m.BINDS_XML is not null),
     ol as (select /*+inline*/plan_hash_value,b.hint
              from v$sql_plan m, xmltable('/*/outline_data/hint' passing xmltype(m.OTHER_XML)
                                 columns hint varchar2(4000) path '/hint') b
             where m.sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue))
               and trim(OTHER_XML) is not null),
     bc  as ( select distinct name,datatype,datatype_string,value_string from v$sql_bind_capture
               where sql_id = :sqlid
                 and last_captured = (select max(last_captured) from v$sql_bind_capture c 
                                       where sql_id = :sqlid
                                       and (not exists (select 1 from v$sql_plan 
                                                        where sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue)))
                                            or exists (select 1 from v$sql_plan p 
                                                       where sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue))
                                                         and c.child_address=p.child_address)))),
     bc1 as ( select distinct b.name,b.datatype,b.datatype_string,b.value_string,b.snap_id from dba_hist_sqlbind b, dba_hist_snapshot s
               where b.sql_id = :sqlid and b.snap_id=s.snap_id and b.instance_number=s.instance_number
                 and not exists (select 1 from bc)
                 and b.snap_id = (select max(c.snap_id) from dba_hist_sqlbind c
                                  where sql_id = :sqlid)),
     cb as (select /*+materialize*/* 
            from (select LISTAGG('var '||substr(name,2)||' '||decode(datatype_string,'VARCHAR2(4001)','CLOB',datatype_string)||';' ,chr(10)) WITHIN GROUP (ORDER BY name) var,
                         LISTAGG('exec '||name||':='||nvl2(value_string,decode(datatype,1,'''','')||value_string||decode(datatype,1,'''','')||';','null;'),chr(10)) WITHIN GROUP (ORDER BY name) exe
                  from bc
                  union all
                  select LISTAGG('var '||substr(name,2)||' '||decode(datatype_string,'VARCHAR2(4001)','CLOB',datatype_string)||';' ,chr(10)) WITHIN GROUP (ORDER BY name) var,
                         LISTAGG('exec '||name||':='||nvl2(value_string,decode(datatype,1,'''','')||value_string||decode(datatype,1,'''','')||';','null;'),chr(10)) WITHIN GROUP (ORDER BY name) exe
                  from bc1
                  group by snap_id)
          where (var is not null or exe is not null)),
     sd as (select PLAN_HASH_VALUE, '1,Loads: '||q.LOADS||'; 2,Load Versions: '||q.LOADED_VERSIONS||'; 3,First Load Time: '||q.FIRST_LOAD_TIME||'; 4,Last Load Time: '||q.LAST_LOAD_TIME||'; 5,User Openings: '||q.USERS_OPENING||'; 6,Parse Calls: '||q.PARSE_CALLS||'; 7,Executions: '||q.EXECUTIONS||'; 8,Sorts(Average): '||round(q.SORTS/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||'; 9,Fetches(Average): '||round(q.FETCHES/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||'; 10,Disk Reads(Average): '||round(q.DISK_READS/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||'; 11,Buffer Gets(Average): '||round(q.BUFFER_GETS/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||'; 12,Elapsed Time(Average): '||ROUND(q.ELAPSED_TIME/1000/1000/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||' seconds; 13,CPU Time(Average): '||ROUND(q.CPU_TIME/1000/1000/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||' seconds; 14,Run Time Memory(Average): '||ROUND(q.RUNTIME_MEM/1024/1024/decode(nvl(q.EXECUTIONS,0),0,1,q.EXECUTIONS),3)||'M' str, 
                   ';' spliter 
            from (select PLAN_HASH_VALUE, sum(LOADS) LOADS, min(FIRST_LOAD_TIME) FIRST_LOAD_TIME, max(LAST_LOAD_TIME) LAST_LOAD_TIME, 
                         sum(LOADED_VERSIONS) LOADED_VERSIONS, sum(USERS_OPENING) USERS_OPENING, sum(EXECUTIONS) EXECUTIONS, 
                         sum(PARSE_CALLS) PARSE_CALLS, sum(SORTS) SORTS, sum(FETCHES) FETCHES, sum(DISK_READS) DISK_READS, 
                         sum(BUFFER_GETS) BUFFER_GETS, max(RUNTIME_MEM) RUNTIME_MEM, sum(CPU_TIME) CPU_TIME, 
                         sum(ELAPSED_TIME) ELAPSED_TIME 
                  from v$sql
                  where sql_id=:sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue)) 
                  group by PLAN_HASH_VALUE
                  union
                  select PLAN_HASH_VALUE, max(LOADS_TOTAL) LOADS, null FIRST_LOAD_TIME, null LAST_LOAD_TIME, 
                         max(LOADED_VERSIONS) LOADED_VERSIONS, 0 USERS_OPENING, max(EXECUTIONS_TOTAL) EXECUTIONS, 
                         max(PARSE_CALLS_TOTAL) PARSE_CALLS, max(SORTS_TOTAL) SORTS, max(FETCHES_TOTAL) FETCHES, 
                         max(DISK_READS_TOTAL) DISK_READS, max(BUFFER_GETS_TOTAL) BUFFER_GETS, 0 RUNTIME_MEM, 
                         max(CPU_TIME_TOTAL) CPU_TIME, max(ELAPSED_TIME_TOTAL) ELAPSED_TIME 
                  from dba_hist_sqlstat
                  where sql_id=:sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue))
                  and not exists (select 1 from v$sqlarea where sql_id = :sqlid and (:planHashValue is NULL or PLAN_HASH_VALUE=to_number(:planHashValue)))
                  group by PLAN_HASH_VALUE) q
           where EXECUTIONS is not null and CPU_TIME is not null and ELAPSED_TIME is not null),
     ss as (select /*+materialize*/*
              from (select PLAN_HASH_VALUE, max(temp_size) temp_size, 0 pga_size 
                      from (select t.SESSION_ADDR,nvl(q.PLAN_HASH_VALUE,99999999999999) PLAN_HASH_VALUE, 
                                   nvl(sum(t.BLOCKS*to_number(p.value)/1024/1024/1024),0) temp_size
                              from v$sort_usage t, v$parameter p, v$session s, v$sql q 
                             where p.name = 'db_block_size' and t.sql_id=:sqlid 
                               and t.SESSION_ADDR=s.saddr(+) and t.sql_id=s.sql_id(+) 
                               and s.sql_id=q.sql_id(+) and s.sql_child_number=q.child_number(+)
                               and (:planHashValue is NULL or q.PLAN_HASH_VALUE is null or q.PLAN_HASH_VALUE=to_number(:planHashValue))
                             group by t.SESSION_ADDR,nvl(q.PLAN_HASH_VALUE,99999999999999))
                     group by PLAN_HASH_VALUE
                     union all
                    select nvl(q.PLAN_HASH_VALUE,99999999999999) PLAN_HASH_VALUE,0 temp_size, nvl(max(PGA_MAX_MEM/1024/1024/1024),0) pga_size 
                      from v$process p, v$session s, v$sql q 
                     where s.paddr=p.addr and s.sql_id = :sqlid
                       and s.sql_id=q.sql_id(+) and s.sql_child_number=q.child_number(+)
                       and (:planHashValue is NULL or q.PLAN_HASH_VALUE is null or q.PLAN_HASH_VALUE=to_number(:planHashValue))
                     group by nvl(q.PLAN_HASH_VALUE,99999999999999)
                     union all
                    select pa.PLAN_HASH_VALUE,nvl(max(TEMP_SPACE_ALLOCATED/1024/1024/1024),0) temp_size, 
                           nvl(max(PGA_ALLOCATED/1024/1024/1024),0) pga_size 
                      from pa
                     group by pa.PLAN_HASH_VALUE))
select /*+no_monitoring*/xxx
  from (
        select 0 PLAN_HASH_VALUE, 1 seq, 0 ID, 'SQL ID: '||:sqlid xxx from dual
        union
        select 0 PLAN_HASH_VALUE, 1 seq, 1 ID, chr(10)||'------------- Last Monitored Binds --------------' xxx from dual where exists (select 1 from mb) and instr(:showOptions,'B')>0
        union
        select 0 PLAN_HASH_VALUE, 2 seq, to_number(sid||'.'||session_serial#||'000001') ID, 
               '--SID: '||sid||','||session_serial#||chr(10)||LISTAGG('var '||substr(b.name,2)||' '||b.data_type,chr(10)) WITHIN GROUP (ORDER BY b.name) xxx 
        from mb b
        where instr(:showOptions,'B')>0
        GROUP BY sid,session_serial#,sql_id
        union 
        select 0 PLAN_HASH_VALUE, 2 seq, to_number(sid||'.'||session_serial#||'000002') ID, 
               '--SID: '||sid||','||session_serial#||chr(10)||LISTAGG('exec '||b.name||':='||decode(instr(b.data_type,'NUMBER'),0,''''||b.value||''';',b.value),chr(10)) WITHIN GROUP (ORDER BY b.name) xxx
        from mb b
        where instr(:showOptions,'B')>0
        GROUP BY sid,session_serial#,sql_id
        union 
        select 0 PLAN_HASH_VALUE, 3 seq, 1 ID, chr(10)||'------------- Last Captured Binds --------------' xxx from dual where exists (select 1 from cb) and instr(:showOptions,'B')>0 and not exists (select 1 from mb)
        union 
        select 0 PLAN_HASH_VALUE, 3 seq, 2 ID, var xxx from cb
        where instr(:showOptions,'B')>0 and not exists (select 1 from mb)
        union 
        select 0 PLAN_HASH_VALUE, 3 seq, 3 ID, exe xxx from cb
        where instr(:showOptions,'B')>0 and not exists (select 1 from mb)
        union
        select 0 PLAN_HASH_VALUE, 10 seq, 0 ID, chr(10)||'------------- SQL Text --------------' xxx from dual
        where instr(:showOptions,'T')>0
        union
        select *
        from (select /*+no_merge*/0 PLAN_HASH_VALUE, 11 seq, level ID, to_char(substr(sql_fulltext,(level-1)*2000+1,2000)) sql_text
              from q
              where instr(:showOptions,'T')>0
              connect by level<=ceil(length(sql_fulltext)/2000))
        UNION
        select distinct PLAN_HASH_VALUE, 30 seq, -1 ID, chr(10)||'------------- SQL Plan (Plan Hash Value:'||PLAN_HASH_VALUE||'; Parsed by schema:'||PARSING_SCHEMA_NAME||') --------------' xxx
        from p
        where instr(:showOptions,'P')>0
        UNION
        select *
        from (SELECT /*+no_merge*/PLAN_HASH_VALUE, 31 seq, ID,
               lpad(nvl2(access_predicates,'*','')||nvl2(filter_predicates,'#','')||ID,6,' ')||lpad('('||nvl(PARENT_ID||'',' ')||')',6,' ')||LPAD(' ',(LEVEL-1))||OPERATION||DECODE(OTHER_TAG,NULL,'','*')||DECODE(OPTIONS,NULL,'',' ('||OPTIONS||')')||DECODE(OBJECT_NAME,NULL,'',' OF '''||OBJECT_NAME||'''')||DECODE(OBJECT_TYPE,NULL,'',' ('||OBJECT_TYPE||')')||DECODE(ID,0,DECODE(OPTIMIZER,NULL,'',' Optimizer='||OPTIMIZER))||DECODE(COST,NULL,'',' (Cost='||COST||DECODE(CARDINALITY,NULL,'',' Card='||CARDINALITY)||DECODE(BYTES,NULL,'',' Bytes='||BYTES)||')') xxx --,OBJECT_NODE OBJECT_NODE_PLUS_EXP
              FROM P
              where instr(:showOptions,'P')>0
              START WITH ID=0
              CONNECT BY PRIOR ID=PARENT_ID AND PRIOR SQL_ID=SQL_ID AND PRIOR PLAN_HASH_VALUE=PLAN_HASH_VALUE)
        UNION
        select distinct PLAN_HASH_VALUE, 33 seq, 0 ID, chr(10)||'------------- Stored Outline (Plan Hash Value:'||PLAN_HASH_VALUE||') --------------' xxx
        from OL
        where instr(:showOptions,'O')>0
        UNION
        select PLAN_HASH_VALUE, 33 seq, 1 ID, '/*+' xxx from OL
        where instr(:showOptions,'O')>0
        UNION
        select PLAN_HASH_VALUE, 33 seq, 2 ID, lpad(' ',3,' ')||'BEGIN_OUTLINE_DATA' xxx from OL
        where instr(:showOptions,'O')>0
        UNION
        select PLAN_HASH_VALUE, 33 seq, 3 ID,lpad(' ',3,' ')||hint xxx from OL
        where instr(:showOptions,'O')>0
        union
        select PLAN_HASH_VALUE, 33 seq, 4 ID, lpad(' ',3,' ')||'END_OUTLINE_DATA' xxx from OL
        where instr(:showOptions,'O')>0
        UNION
        select PLAN_HASH_VALUE, 33 seq, 5 ID, '*/' xxx from OL
        where instr(:showOptions,'O')>0
        UNION
        select distinct PLAN_HASH_VALUE, 35 seq, 0 ID, chr(10)||'------------- Peeked Binds (Plan Hash Value:'||PLAN_HASH_VALUE||') --------------' xxx
        from pb
        where instr(:showOptions,'K')>0
        UNION
        select PLAN_HASH_VALUE, 35 seq, 1 ID,
               LISTAGG('var '||substr(name,2)||' '||data_type,chr(10)) WITHIN GROUP (ORDER BY name) xxx
        from pb
        where instr(:showOptions,'K')>0
        group by PLAN_HASH_VALUE
        UNION
        select PLAN_HASH_VALUE, 35 seq, 2 ID,LISTAGG('exec '||name||':='||decode(instr(data_type,'NUMBER'),0,''''||value||''';',value),chr(10)) WITHIN GROUP (ORDER BY name) xxx
        from pb
        where instr(:showOptions,'K')>0
        group by PLAN_HASH_VALUE
        UNION
        select distinct PLAN_HASH_VALUE, 36 seq, -1 ID, chr(10)||'------------- Predicate Information (Plan Hash Value:'||PLAN_HASH_VALUE||') --------------' xxx
        from P 
        where ((access_predicates is not null) or (filter_predicates is not null))
        and instr(:showOptions,'D')>0
        UNION
        select PLAN_HASH_VALUE, 36 seq, ID,lpad(id,3,' ')||' Access: '||access_predicates xxx
        from P
        where (access_predicates is not null)
        and instr(:showOptions,'D')>0
        union
        select PLAN_HASH_VALUE, 36 seq, ID,lpad(id,3,' ')||' Filter: '||filter_predicates xxx
        from P
        where (filter_predicates is not null)
        and instr(:showOptions,'D')>0
        union
        select distinct P.PLAN_HASH_VALUE, 50 seq, -1 ID, chr(10)||'------------- Plan Loading (Plan Hash Value:'||P.PLAN_HASH_VALUE||') --------------' xxx
        from P, PL
        where P.PLAN_HASH_VALUE=PL.PLAN_HASH_VALUE and p.ID=SQL_PLAN_LINE_ID
        and total_waits>0
        and instr(:showOptions,'L')>0
        UNION
        select P.PLAN_HASH_VALUE, 50 seq, PL.TOTAL_WAITS-PL.WAITS ID, 
               lpad(P.ID,3,' ')||': '||RPAD(PL.sql_plan_op,50,' ')||rpad('#',round(pl.waits/pl.total_waits*50),'#')||'('||round(pl.waits/pl.total_waits*100,2)||'%)' xxx
        from P, PL
        where P.PLAN_HASH_VALUE=PL.PLAN_HASH_VALUE and p.ID=SQL_PLAN_LINE_ID
        and PL.total_waits>0
        and instr(:showOptions,'L')>0
        union
        select distinct PLAN_HASH_VALUE, 55 seq, -1 ID, chr(10)||'------------- Waits Events (Plan Hash Value:'||PLAN_HASH_VALUE||') --------------' xxx
        from we
        where total_waits>0
        and instr(:showOptions,'W')>0
        UNION
        select PLAN_HASH_VALUE, 55 seq, TOTAL_WAITS-WAITS ID, 
               rpad(event||' on '||wait_object,75,' ')||rpad('#',round(waits/total_waits*50),'#')||'('||round(waits/total_waits*100,2)||'%)' xxx
        from we 
        where total_waits>0
        and instr(:showOptions,'W')>0
        union
        select PLAN_HASH_VALUE, 60 seq, 1 ID, chr(10)||'------------- Statistics Data '||decode(PLAN_HASH_VALUE,99999999999999,'','(Plan Hash Value:'||PLAN_HASH_VALUE||')')||'--------------' xxx from sd
        where instr(:showOptions,'S')>0
        union
        select PLAN_HASH_VALUE, 60 seq, 
               10+to_number(substr(str,1,instr(str,',')-1)) ID, substr(str,instr(str,',')+1) xxx
          from (select PLAN_HASH_VALUE, trim(regexp_substr(str, '[^'||spliter||']+', 1, level)) str from sd 
                connect by level <= length (regexp_replace (str, '[^'||spliter||']+'))  + 1)
        union
        select PLAN_HASH_VALUE, 60 seq, 101 ID, 
               'PGA Size(Maximum): '||round(max(nvl(pga_size,0)),3)||'G' xxx 
          from ss
         where instr(:showOptions,'S')>0
         group by PLAN_HASH_VALUE
        union
        select PLAN_HASH_VALUE, 60 seq, 102 ID, 
               'Temp Space(Maximum): '||round(max(nvl(temp_size,0)),3)||'G' xxx 
          from ss
         where instr(:showOptions,'S')>0
         group by PLAN_HASH_VALUE
         order by PLAN_HASH_VALUE, SEQ, ID, XXX)
;

undef 1 2 3
set head on
clear columns
