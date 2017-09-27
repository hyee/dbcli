/*[[
Show active SQLs/processes/sessions. Usage: @@NAME [-a|-i|-k] [-u]
  --[[
      &filter:  {
        default ={1=1},
        a={status='ACTIVE'},
        i={status='INACTIVE'},
        k={status='KILLED'}
      }
      
      &usr: default={1=1}, u={username=nvl('&0',sys_context('userenv','current_schema'))}
      @pname: 11={pname,}, default={}
  ]]--
]]*/
set feed off



prompt  List of processes      
prompt  =================
col last_call_et format smhd2
SELECT s.sid || ',' || s.serial# || ',@' || s.inst_id "SID",
       p.spid,
       substr(s.username, 1, 8) username,
       s.osuser,
       s.command,
       decode(s.command, 1,'Create table'          , 2,'Insert'
                       , 3,'Select'                , 6,'Update'
                       , 7,'Delete'                , 9,'Create index'
                       ,10,'Drop index'            ,11,'Alter index'
                       ,12,'Drop table'            ,13,'Create seq'
                       ,14,'Alter sequence'        ,15,'Alter table'
                       ,16,'Drop sequ.'            ,17,'Grant'
                       ,19,'Create syn.'           ,20,'Drop syn.'
                       ,21,'Create view'           ,22,'Drop view'
                       ,23,'Validate index'        ,24,'create proced.'
                       ,25,'Alter procedure'       ,26,'Lock table'
                       ,42,'Alter session'         ,44,'Commit'
                       ,45,'Rollback'              ,46,'Savepoint'
                       ,47,'PL/SQL Exec'           ,48,'Set Transaction'
                       ,60,'Alter trigger'         ,62,'Analyse Table'
                       ,63,'Analyse index'         ,71,'Create Snapshot Log'
                       ,72,'Alter Snapshot Log'    ,73,'Drop Snapshot Log'
                       ,74,'Create Snapshot'       ,75,'Alter Snapshot'
                       ,76,'drop Snapshot'         ,85,'Truncate table'
                       , 0,'No command', '? : '||s.command) commande,
       to_char(s.logon_time, 'DD-MM-YY HH24:MI') logon,
       substr(s.status, 1, 4) status,
       last_call_et,
       s.lockwait,
       &pname
       Substr(regexp_replace(nvl(s.module,s.program),' *\(.*\)$'), 1, 20) program,
       sw.event,
       s.sql_id
FROM   (SELECT * FROM gv$session WHERE &filter and &usr) s, gv$process p, gv$session_wait sw
WHERE  s.paddr = p.addr
AND    sw.sid = s.sid
AND    s.inst_id = p.inst_id
AND    s.sid = sw.sid
AND    s.inst_id = sw.inst_id
AND    s.username IS NOT NULL
ORDER  BY s.status DESC, s.last_call_et DESC, P.spid;



prompt  Active / Inactive Sessions  
prompt  ==========================

SELECT '--  Time : ' || TIME || ' - Process : ' || Proc || ' - Session ' || Sess Status
FROM   (SELECT To_Char(SYSDATE, 'HH24:MI') TIME FROM Dual), (SELECT COUNT(*) Proc FROM GV$Process), (SELECT COUNT(*) Sess FROM GV$Session);

SELECT Initcap(S.Status) status, COUNT(*) nb_sess FROM GV$Session S  where &filter and &usr GROUP BY Initcap(S.Status);


prompt  Active Sessions In Progress
prompt  ===========================
col Time_Left format smhd2
SELECT sn.sid || ',' || sn.serial# || ',@' || sn.inst_id "SID",
       sn.sql_id top_sql_id,
       sl.sql_id,
       substr(sn.username, 1, 8) username,
       Round(ELAPSED_SECONDS / 60, 2) "Costed(Min)",
       round((TIME_REMAINING) / 60,2) "Remain(Min)",
       round(100*sofar/totalwork,2) "Pct(%)",
       sl.message,
       sn.machine machine,
       sn.program program,
       sn.module modu
FROM   gv$session_longops sl, (SELECT * FROM gv$session WHERE &filter and &usr) sn
WHERE  sl.inst_id = sn.inst_id
AND    sn.status = 'ACTIVE'
AND    sl.sid = sn.sid
AND    sl.sofar != sl.totalwork;

prompt  Running SQLs 
prompt  ============
col last_loaded format smhd2
SELECT /*+ BDAGEVIL leading(se) */sql_id, COUNT(DISTINCT child_number) child_nums, SUM(users_executing) users, username,
       (sysdate-min(to_date(LAST_LOAD_TIME,'YYYY-MM-DD/HH24:MI:SS')))*86400 last_loaded,
       substr(trim(regexp_replace(REPLACE(max(sql_text), chr(0)),'['|| chr(10) || chr(13) || chr(9) || ' ]+',' ')),1,150) sql_text
FROM   (SELECT s.*,parsing_schema_name username from gv$sql s) s
WHERE  s.users_executing > 0
AND    s.sql_text NOT LIKE '%BDAGEVIL%'
AND    &usr
group by sql_id,parsing_schema_name
order by users desc;
