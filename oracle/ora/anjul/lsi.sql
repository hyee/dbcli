/*[[
Show gv$session [-a|-i|-k]
  --[[
      &filter:  {
        default ={1=1},
        a={status='ACTIVE'},
        i={status='INACTIVE'},
        k={status='KILLED'}
      }
  ]]--
]]*/
set feed off
prompt
prompt -- ----------------------------------------------------------------------- ---
prompt --   List of oracle's processes                                            ---
prompt -- ----------------------------------------------------------------------- ---

select
       s.sid ||','|| s.serial#||',@'||s.inst_id "SID"
     , p.spid
     , substr(s.username,1,8) username
--     , s.terminal
     , s.osuser
     , s.command
     , decode(s.command, 1,'Create table'          , 2,'Insert'
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
                       , 0,'No command', '? : '||s.command) commande
       , to_char(s.logon_time,'DD-MM-YY HH24:MI') logon
       , substr(s.status,1,4) status
       , floor(s.last_call_et/3600)||':'||
         floor(mod(s.last_call_et,3600)/60)||':'||
         mod(mod(s.last_call_et,3600),60)              last_call_et
       , s.lockwait
     , Substr(s.program,1,20) program, sw.event , s.sql_id
  from
       gv$session s
     , gv$process p
     , gv$session_wait sw
 where
       s.paddr  =  p.addr
and    sw.sid  = s.sid
and s.inst_id = p.inst_id
and s.sid = sw.sid
and s.inst_id = sw.inst_id
and    s.username is not null
and &filter
 order
     by s.status desc
      , s.last_call_et desc
    , P.spid
;


Prompt
prompt
prompt -- ----------------------------------------------------------------------- ---
prompt --   Active / Inactive Sessions                                            ---
prompt -- ----------------------------------------------------------------------- ---

Select
       '--  Time : '||Time||' - Process : '||Proc||' - Session '||Sess            Status
 From
       ( Select To_Char(Sysdate, 'HH24:MI')     Time
         From Dual
       )
     , ( Select Count(*)                Proc
         From GV$Process
       )
     , ( Select Count(*)                 Sess
         From GV$Session
        )
;



Prompt


Select
     Initcap(S.Status)    status
     , Count(*)            nb_sess
  From
       GV$Session S
 Group
    By Initcap(S.Status)
;



Prompt
prompt
prompt -- ----------------------------------------------------------------------- ---
prompt --   Active / Sessions In Progress ...                                     ---
prompt -- ----------------------------------------------------------------------- ---

Select
       sn.sid
     , substr(sn.username,1,8)         username
     , Trunc(sl.sofar/sl.totalwork * 100) pct
     , sn.machine                    machine
     , sn.program                 program
     , sn.module                    modu
     , sl.message
     , to_char(start_time,'DD-MON-YY HH:MI:SS')     Sta_Time
     , to_char(last_update_time,'DD-MON-YY HH:MI:SS') LUTime
     , To_Char(To_Date(TIME_REMAINING,'SSSSS'),'HH24:MI:SS') Time_Left
  From
       gv$session_longops sl
     , gv$session sn
 where
       sl.inst_id = sn.inst_id
       and sn.status = 'ACTIVE'
   and
       sl.sid = sn.sid
   and
       sl.sofar       != sl.totalwork
;
