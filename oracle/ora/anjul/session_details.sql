/*[[  Session Details. Usage: @@NAME <sid> <inst_id>
    --[[
        @ALIAS: sd
    --]]
]]*/

DECLARE
   v_sid           gv$session.sid%TYPE;
   v_inst_id       gv$session.inst_id%TYPE;
   v_object_name   dba_objects.object_name%TYPE;
   v_owner         dba_segments.owner%TYPE;
   v_segment_name  VARCHAR2(60);
   v_segment_type  dba_segments.segment_type%TYPE;
   v_file_name     dba_data_files.file_name%TYPE;
   sess_details    gv$session%ROWTYPE;
   proc_details    gv$process%ROWTYPE;

   ----------------------------------------------------------
   -- Convert a number of seconds into a more readable format
   -- Convert duration into the equivalent number of days,
   --    hours, minutes and seconds.
   ----------------------------------------------------------
   FUNCTION appdba_format_duration (p_seconds NUMBER) RETURN VARCHAR2
   IS
      l_duration_str   VARCHAR2(30);
   BEGIN
      ---------------------------------------------------
      -- If duration is less than 3 days, display the format as X hours Y mins Z seconds
      ---------------------------------------------------
      IF p_seconds/3600/24 < 3 THEN
      -- Hours
         IF p_seconds/3600 > 1 THEN
            l_duration_str := l_duration_str || LTRIM(TO_CHAR(TRUNC(p_seconds/3600),'990'));
            IF TRUNC(p_seconds/3600) = 1 THEN
               l_duration_str := l_duration_str || ' hour ';
            ELSE
               l_duration_str := l_duration_str || ' hours ';
            END IF;
         END IF;
         -- Minutes
         IF p_seconds/60 > 1 THEN
            l_duration_str := l_duration_str || LTRIM(TO_CHAR(MOD(TRUNC(p_seconds/60),60),'90'));
            IF MOD(TRUNC(p_seconds/60),60) = 1 THEN
               l_duration_str := l_duration_str || ' min ';
            ELSE
               l_duration_str := l_duration_str || ' mins ';
            END IF;
         END IF;
         l_duration_str := l_duration_str || TO_CHAR(TRUNC(MOD(p_seconds,60)));
         IF MOD(p_seconds,60) = 1 THEN
            l_duration_str := l_duration_str || ' sec';
         ELSE
            l_duration_str := l_duration_str || ' secs';
         END IF;
      ---------------------------------------------------
      -- If duration is greater than 3 days, display the format as X days Y.Z hours
      ---------------------------------------------------
      ELSE
         -- Days
         l_duration_str := l_duration_str || LTRIM(TO_CHAR(TRUNC(p_seconds/3600/24),'990')) || ' days ';
         -- Hours
         l_duration_str := l_duration_str || LTRIM(TO_CHAR(MOD(p_seconds/3600,24),'90.9')) || ' hours';
      END IF;

      RETURN l_duration_str;
   END appdba_format_duration;


   ----------------------------------------------------------
   -- Convert a number of bytes into a more readable format
   -- Convert duration into the equivalent number of bytes,
   --    kb, mb or gb
   ----------------------------------------------------------
   FUNCTION appdba_format_size (p_bytes NUMBER) RETURN VARCHAR2
   IS
      l_size_str   VARCHAR2(30);
   BEGIN
      ---------------------------------------------------
      -- If size is less than 1 KB or size is less than 10 KB and is not an exact multiple of KB
      ---------------------------------------------------
      IF p_bytes < 1024 OR ( MOD(p_bytes,1024) <> 0 AND p_bytes < 10*1024) THEN
         l_size_str := p_bytes || ' BYTES';
      ---------------------------------------------------
      -- If size is less than 1 MB
      ---------------------------------------------------
      ELSIF p_bytes < 1024*1024 THEN
         l_size_str := TRUNC(p_bytes/1024,2) || ' KB';
      ---------------------------------------------------
      -- If size is less than 1 GB
      ---------------------------------------------------
      ELSIF p_bytes < 1024*1024*1024 THEN
         l_size_str := TRUNC(p_bytes/1024/1024,2) || ' MB';
      ELSE
         l_size_str := TRUNC(p_bytes/1024/1024/1024,2) || ' GB';
      END IF;

      RETURN l_size_str;
   END appdba_format_size;

   ---------------------------------------------------
   -- Display the SQL statement for a given HASH_VALUE
   ---------------------------------------------------
   PROCEDURE print_sql_statement (p_hash_value gv$sqltext.hash_value%TYPE, p_inst_id gv$sqltext.inst_id%TYPE)
   IS
      curr_text    VARCHAR2(2000);
      MAX_LINE     CONSTANT NUMBER := 80;
   BEGIN
      FOR c1 IN (    SELECT   sqlt.sql_text
                     FROM     gv$sqltext_with_newlines sqlt
                     WHERE    sqlt.hash_value = p_hash_value
                     AND      sqlt.inst_id = p_inst_id
                     ORDER BY sqlt.piece ) LOOP

         curr_text := curr_text || c1.sql_text;

         -- If lines have embedded newlines, break at these points and print
         --  chunks individually using PUT_LINE (which can only handle 255 chars)
         WHILE INSTR(curr_text, CHR(10)) > 0 LOOP
            DBMS_OUTPUT.PUT_LINE(SUBSTR(curr_text, 1, INSTR(curr_text,CHR(10))-1));
            curr_text := SUBSTR(curr_text,INSTR(curr_text,CHR(10))+1);
         END LOOP;

         -- If lines are still longer than MAX_LINES (most likely due to no
         --  newline characters in the original SQL) break lines at a space ' '
         --  to form lines of less than MAX_LINE characters
         WHILE LENGTH(curr_text) > MAX_LINE LOOP
            -- If there is a space ' ' in the first MAX_LINE characters, break on the
            --  last space in this range
            IF INSTR(SUBSTR(curr_text, 1, MAX_LINE), ' ') > 0 THEN
               DBMS_OUTPUT.PUT_LINE( SUBSTR(curr_text, 1, INSTR(curr_text, ' ', MAX_LINE-LENGTH(curr_text))));
               curr_text := SUBSTR(curr_text, INSTR(curr_text, ' ', MAX_LINE-LENGTH(curr_text)));
            -- If there is no space ' ' in the first MAX_LINE characters, break on
            --  a comma if one exists
            ELSIF INSTR(SUBSTR(curr_text, 1, MAX_LINE), ',') > 0 THEN
               DBMS_OUTPUT.PUT_LINE( SUBSTR(curr_text, 1, INSTR(curr_text, ',', MAX_LINE-LENGTH(curr_text))));
               curr_text := SUBSTR(curr_text, INSTR(curr_text, ',', MAX_LINE-LENGTH(curr_text)));
            -- If there is no space or comma in the first MAX_LINE characters, break
            --  at MAX_LINE characters (even if it breaks mid-word
            -- TO-DO: Improve code so that SQL will break at other suitable characters (eg. +, -, TAB, etc.)
            --         ideally without many IF-ELSE statements
            ELSE
               DBMS_OUTPUT.PUT_LINE( SUBSTR(curr_text, 1, MAX_LINE));
               curr_text := SUBSTR(curr_text, MAX_LINE);
            END IF;
         END LOOP;
      END LOOP;

      DBMS_OUTPUT.PUT_LINE(curr_text);
   END print_sql_statement;

BEGIN

   v_sid     := '&V1';
   v_inst_id := NVL('&V2',1);

   ---------------------------------------------------
   -- Extract the details from V$SESSION and V$PROCESS
   ---------------------------------------------------
   BEGIN
     SELECT s.* INTO sess_details
       FROM gv$session s
       WHERE s.sid     = v_sid
       AND   s.inst_id = v_inst_id;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         DBMS_OUTPUT.PUT_LINE('Unable to find SID <' || v_sid || '> on instance <' || v_inst_id || '>. Exiting.');
         RETURN;
   END;

   SELECT p.* INTO proc_details
     FROM  gv$process p
     WHERE p.addr = sess_details.paddr
     AND   p.inst_id = sess_details.inst_id;

   ---------------------------------------------------
   -- General Session Details
   ---------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Now         : '|| TO_CHAR(sysdate,'Dy DD-MON-YYYY HH24:MI:SS'));
   DBMS_OUTPUT.PUT_LINE('SID/Serial  : '|| sess_details.sid || ',' || sess_details.serial#);
   DBMS_OUTPUT.PUT_LINE('Instance ID : '|| sess_details.inst_id);
   DBMS_OUTPUT.PUT_LINE('Foreground  : '|| 'PID: ' || sess_details.process ||
                                             ' - ' || sess_details.program);
   DBMS_OUTPUT.PUT_LINE('Shadow      : '|| 'PID: ' || proc_details.spid ||
                                             ' - ' || proc_details.program);
   FOR c1 IN (       SELECT   network_service_banner
                     FROM     gv$session_connect_info
                     WHERE    network_service_banner LIKE '%Protocol%'
                     AND      sid = sess_details.sid
                     AND      inst_id = sess_details.inst_id) LOOP
         DBMS_OUTPUT.PUT_LINE('Protocol    : '|| c1.network_service_banner);
   END LOOP;
   DBMS_OUTPUT.PUT_LINE('OS User     : '|| sess_details.osuser  || ' on ' ||
                                           sess_details.machine ||
                                   ' (' || sess_details.module  || ')');
   DBMS_OUTPUT.PUT_LINE('Ora User    : '|| sess_details.username);
   DBMS_OUTPUT.PUT_LINE('Status Flags: '|| sess_details.status || ' ' ||
                                           sess_details.server || ' ' ||
                                           sess_details.type);
   DBMS_OUTPUT.PUT_LINE('Login Time  : '||
                            TO_CHAR(sess_details.logon_time,
                                    'Dy DD-MON-YYYY HH24:MI:SS') || ' - ' ||
                            appdba_format_duration((sysdate-sess_details.logon_time)*60*60*24));
   DBMS_OUTPUT.PUT_LINE('Last Call   : '||
                            TO_CHAR(sysdate-(sess_details.last_call_et/60/60/24),
                                    'Dy DD-MON-YYYY HH24:MI:SS') || ' - ' ||
                            appdba_format_duration(sess_details.last_call_et));


   ---------------------------------------------------
   -- SQL Statements
   ---------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Current SQL : ' ||
                        RPAD('Address ''' || sess_details.sql_address || ''' ',19) ||
                        'Hash Value ''' || sess_details.sql_hash_value || '''');
   print_sql_statement(sess_details.sql_hash_value, sess_details.inst_id);


   DBMS_OUTPUT.PUT_LINE('Previous SQL: ' ||
                        RPAD('Address ''' || sess_details.prev_sql_addr || ''' ',19) ||
                        'Hash Value ''' || sess_details.prev_hash_value || '''');
   print_sql_statement(sess_details.prev_hash_value, sess_details.inst_id);


   ---------------------------------------------------
   -- Wait Details
   ---------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Session Wait:');
   FOR c1 IN (   SELECT     w.state, w.event, w.p1, w.p2, w.p3, n.parameter1 p1n
                          , n.parameter2 p2n, n.parameter3 p3n, w.seconds_in_wait secs
                 FROM       gv$session_wait w
                          , gv$event_name n
                 WHERE      w.sid = sess_details.sid
                 AND        w.inst_id = sess_details.inst_id
                 AND        w.event = n.name(+)
          AND        w.inst_id = n.inst_id(+)) LOOP

      IF c1.state <> 'WAITING' THEN
         DBMS_OUTPUT.PUT_LINE(CHR(9) || 'Not Waiting. Details of Previous wait:');
         DBMS_OUTPUT.PUT_LINE(CHR(9) || c1.state || ': ' || c1.event || ': ' ||
                           appdba_format_duration(c1.secs));
      ELSE
         DBMS_OUTPUT.PUT_LINE(CHR(9) || 'Currently Waiting: ' ||
                           c1.event || ': ' || appdba_format_duration(c1.secs));
      END IF;

      -- If we are waiting on a particular block we can obtain the details
      --  of the segment this belongs to
      IF c1.p1n = 'file#' AND c1.p2n = 'block#' THEN
--
--         SELECT   e.owner
--                , e.segment_name || DECODE(e.partition_name,NULL,NULL,':'||e.partition_name)
--                , e.segment_type
--                , f.file_name
--         INTO   v_owner, v_segment_name, v_segment_type, v_file_name
--         FROM   dba_extents    e
--              , dba_data_files f
--         WHERE  e.file_id = f.file_id
--         AND    e.file_id = c1.p1
--         AND    c1.p2 BETWEEN e.block_id AND e.block_id + e.blocks - 1;
--
         DBMS_OUTPUT.PUT_LINE(CHR(9) || CHR(9) || RPAD(LOWER(v_segment_type) || ':',17) ||
                              v_owner || '.' || v_segment_name);
         DBMS_OUTPUT.PUT_LINE(CHR(9) || CHR(9) || RPAD('file:',17) || v_file_name);
         DBMS_OUTPUT.PUT_LINE(CHR(9) || CHR(9) || RPAD(c1.p3n || ':',17) || c1.p3);
         DBMS_OUTPUT.PUT_LINE(CHR(9) || CHR(9) || RPAD(c1.p2n || ':',17) || c1.p2);
      ELSE
         DBMS_OUTPUT.PUT_LINE(CHR(9) || CHR(9) || '(' ||
                              c1.p1n || ':' || c1.p1 || ' ' ||
                              c1.p2n || ':' || c1.p2 || ' ' ||
                              c1.p3n || ':' || c1.p3 || ')');
      END IF;
   END LOOP;


   ---------------------------------------------------
   -- Locks Requested and Held
   ---------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Locks       :');
   FOR c1 IN (   SELECT   l.type
                        , l.lmode
                        , l.request
                        , l.id1
                        , l.id2
                        , l.block
                        , l.ctime
                        , DECODE(l.type,
                                 'TM', 'Table/DML',    'TX', 'Transaction',
                                 'UL', 'PLS USR LOCK', 'BL', 'BUF HASH TBL',
                                 'CF', 'CONTROL FILE', 'CI', 'CROSS INST F',
                                 'DF', 'DATA FILE   ', 'CU', 'CURSOR BIND ',
                                 'DL', 'Direct Load',  'DM', 'MOUNT/STRTUP',
                                 'DR', 'RECO LOCK   ', 'DX', 'Distrib Trans',
                                 'FS', 'FILE SET    ', 'IN', 'INSTANCE NUM',
                                 'FI', 'SGA OPN FILE', 'IR', 'INSTCE RECVR',
                                 'IS', 'GET STATE   ', 'IV', 'LIBCACHE INV',
                                 'KK', 'LOG SW KICK ', 'JI', 'Mat View Refresh',
                                 'LS', 'LOG SWITCH  ', 'MM', 'MOUNT DEF   ',
                                 'MR', 'MEDIA RECVRY', 'PF', 'PWFILE ENQ  ',
                                 'PR', 'PROCESS STRT', 'PS', 'Parallel Slave Sync',
                                 'RT', 'REDO THREAD ', 'SC', 'SCN ENQ     ',
                                 'RW', 'ROW WAIT    ',
                                 'SM', 'SMON LOCK   ', 'SN', 'SEQNO INSTCE',
                                 'SQ', 'SEQNO ENQ   ', 'ST', 'SPACE TRANSC',
                                 'SV', 'SEQNO VALUE ', 'TA', 'GENERIC ENQ ',
                                 'TD', 'DLL ENQ     ', 'TE', 'EXTEND SEG  ',
                                 'TO', 'Global Temp Table',
                                 'TS', 'TEMP SEGMENT', 'TT', 'TEMP TABLE  ',
                                 'UN', 'USER NAME   ', 'WL', 'WRITE REDO  ',
                                 'TYPE=' || l.type)   type_desc
                        , DECODE(l.lmode
                                , 0, 'NONE'
                                , 1, 'NULL'
                                , 2, 'Row Share'
                                , 3, 'Row Exclusive'
                                , 4, 'Share'
                                , 5, 'Share Row Excl'
                                , 6, 'Exclusive'
                                , TO_CHAR(l.lmode) ) lmode_desc
                       , DECODE(l.request
                                , 0, 'NONE'
                                , 1, 'NULL'
                                , 2, 'Row Share'
                                , 3, 'Row Exclusive'
                                , 4, 'Share'
                                , 5, 'Share Row Exclusive'
                                , 6, 'Exclusive'
                                , TO_CHAR(l.request) ) lrequest_desc
                 FROM   gv$lock l
                 WHERE  l.sid   = sess_details.sid
         AND    l.inst_id = sess_details.inst_id
                 ORDER BY  l.request, l.type, l.ctime, l.id1, l.id2) LOOP

      -- ID1 refers to an object_id for the below locks
      IF c1.type IN ('MR','TD','TM','TO','JI','DL') THEN
         BEGIN
            SELECT owner || '.' || object_name || DECODE(subobject_name,NULL,NULL,':'||subobject_name)
            INTO v_object_name
            FROM dba_objects
            WHERE object_id = c1.id1;
         EXCEPTION
            WHEN no_data_found THEN
               v_object_name := 'Object ID (' || c1.id1 || ') not found in DBA_OBJECTS';
         END;
      ELSIF c1.type = 'RW' THEN
         v_object_name := 'FILE#='   || SUBSTR(c1.id1,1,3) ||
                ' BLOCK#=' || SUBSTR(c1.id1,4,5) ||
                ' ROW='    || c1.id2;

      -- Decode the Transaction ID (Slot in RBS header)
      -- When requesting a lock on a transaction ...
      --  * Session may be attempting to obtain a lock on a row, and we can obtain these details
      --  * Or session may be waiting for a free ITL slot in a block and is waiting for a
      --     transaction using one of these slots to complete

      ELSIF c1.type = 'TX' THEN
         v_object_name := NULL;
         IF c1.request > 1 THEN
            BEGIN
               SELECT o.object_name || ' ''' ||
                  dbms_rowid.rowid_create(1
                           ,o.data_object_id
                           ,sess_details.row_wait_file#
                           ,sess_details.row_wait_block#
                           ,sess_details.row_wait_row#) || ''' : '
               INTO v_object_name
               FROM dba_objects o
               WHERE sess_details.row_wait_obj# = o.OBJECT_ID;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_object_name := 'ITL Slot (No Row Details) : ';
            END;
         END IF;
         SELECT  v_object_name || name ||
            ', Slot ' || TO_CHAR(BITAND(c1.id1,TO_NUMBER('ffff','xxxx'))+0) ||
            ', Seq '  || c1.id2
         INTO v_object_name
         FROM v$rollname
         WHERE USN=TRUNC(c1.id1/POWER(2,16));
      ELSIF c1.type = 'WL' THEN
         v_object_name := 'REDO LOG FILE#=' || c1.id1;
      ELSIF c1.type = 'PS' THEN
         v_object_name := 'P' || LPAD(c1.id2,3,'0');
      ELSIF c1.type = 'RT' THEN
         v_object_name := 'THREAD=' || c1.id1;
      ELSE
         v_object_name := RPAD('ID1=' || c1.id1,10) || ' ID2=' || c1.id2;
      END IF;

      DBMS_OUTPUT.PUT(CHR(9));
      IF c1.lmode > 1 THEN
         DBMS_OUTPUT.PUT(RPAD('Holding', 11));
         DBMS_OUTPUT.PUT(RPAD(c1.lmode_desc  || ' (' || c1.lmode || ') ',20));
      ELSE
         DBMS_OUTPUT.PUT(RPAD('Requesting', 11));
         DBMS_OUTPUT.PUT(RPAD(c1.lrequest_desc  || ' (' || c1.request || ') ',20));
      END IF;
      DBMS_OUTPUT.PUT(RPAD(c1.type_desc   || ' (' || c1.type  || ') ',24));
      DBMS_OUTPUT.PUT(LPAD(appdba_format_duration(c1.ctime), 14) || ' : ');
      DBMS_OUTPUT.PUT(v_object_name);
      IF c1.block > 0 THEN
         DBMS_OUTPUT.PUT(' [Blocking!]');
      END IF;
      DBMS_OUTPUT.PUT_LINE('');
      IF c1.request > 1 THEN
         FOR c2 IN ( SELECT *
                FROM  gv$lock
                WHERE id1 = c1.id1
                AND   id2 = c1.id2
                AND   block > 0) LOOP
            FOR c3 IN (    SELECT *
                  FROM gv$session
                  WHERE sid = c2.sid
                  AND   inst_id = c2.inst_id ) LOOP
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9));
               DBMS_OUTPUT.PUT_LINE('Blocked by:');
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('SID/Serial  : ' || c3.sid || ',' || c3.serial#);
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('Instance ID : ' || c3.inst_id);
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('Foreground  : PID: ' || c3.process ||
                  ' - ' || c3.program);
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('User        : ' || c3.username ||
                  ' (' || c3.osuser || ' on ' || c3.machine || ')');
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('Status      : ' || c3.status);
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('Login Time  : ' ||
                  to_char(c3.logon_time, 'Dy DD-MON-YYYY HH24:MI:SS') || ' - ' ||
                  appdba_format_duration((sysdate-c3.logon_time)*60*60*24));

               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT_LINE('Last Call   : ' ||
                               to_char(sysdate-(c3.last_call_et/60/60/24),
                     'Dy DD-MON-YYYY HH24:MI:SS') || ' - ' ||
                  appdba_format_duration(c3.last_call_et));
               DBMS_OUTPUT.PUT(CHR(9) || CHR(9) || ' ');
               DBMS_OUTPUT.PUT('Session Wait: ');
                            FOR c4 IN (     SELECT    *
                                         FROM    gv$session_wait
                                         WHERE   sid = c2.sid
                                         AND     inst_id = c2.inst_id) LOOP
                                    DBMS_OUTPUT.PUT(c4.state || ': ' || c4.event);
                            END LOOP;
               DBMS_OUTPUT.PUT_LINE('');
            END LOOP;
         END LOOP;
      END IF;
   END LOOP;


   ---------------------------------------------------
   -- Long Operations
   ---------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Long Ops    :');
   FOR c1 IN (   SELECT     lo.*
                 FROM      gv$session_longops    lo
                 WHERE     lo.sid = sess_details.sid
                 AND       lo.inst_id = sess_details.inst_id
                 AND       lo.time_remaining > 0
                 ORDER BY  lo.start_time) LOOP
      DBMS_OUTPUT.PUT_LINE(CHR(9) || c1.MESSAGE || ': ' ||
            appdba_format_duration(c1.time_remaining) || ' remaining (' ||
            TO_CHAR(SYSDATE+(c1.time_remaining/24/60/60),'DD-Mon-YY HH24:MI:SS') || ')');
   END LOOP;


   ----------------------------------------------------
   -- Transaction / Rollback Usage details
   ----------------------------------------------------
   DBMS_OUTPUT.PUT_LINE('Transaction :');
   FOR c1 IN (  SELECT  r.name
                      , xidusn                usn
                      , xidslot               slot
                      , xidsqn                seq
                      , t.used_urec           records
                      , t.used_ublk*p.value   used_bytes
                      , DECODE( t.space
                              , 'YES', 'SPACE TX'
                              , DECODE( t.recursive
                                      , 'YES', 'RECURSIVE TX'
                                      , DECODE( t.noundo
                                              , 'YES', 'NO UNDO TX'
                                              , t.status)))                   status
                      , a.value                                               commits
                      , TO_DATE(start_time,'MM/DD/YY HH24:MI:SS')             start_time
                FROM    gv$transaction     t
                      , v$rollname         r
                      , gv$sesstat         a
                      , (SELECT value
                         FROM   gv$parameter
                         WHERE  name = 'db_block_size'
                         AND    inst_id = sess_details.inst_id)  p
                WHERE   t.xidusn      = r.usn
                AND     t.ses_addr    = sess_details.saddr
                AND     t.inst_id     = sess_details.inst_id
                AND     a.sid         = sess_details.sid
                AND     a.inst_id     = sess_details.inst_id
                AND     a.statistic#  = 4 ) LOOP
      DBMS_OUTPUT.PUT_LINE(CHR(9) || 'Undo Segment: ' || c1.name || ' (' || c1.usn || ') Slot#: ' || c1.slot || ' Seq#: ' || c1.seq);
      DBMS_OUTPUT.PUT_LINE(CHR(9) || '  Transaction Status: ' || c1.status);
      DBMS_OUTPUT.PUT_LINE(CHR(9) || '  Undo Generated    : ' || c1.records || ' record(s) (' || appdba_format_size(c1.used_bytes) || ')');
      DBMS_OUTPUT.PUT_LINE(CHR(9) || '  Transaction Start : ' || TO_CHAR(c1.start_time,'DD-MON-YYYY HH24:MI:SS') ||
                    ' (' || appdba_format_duration((SYSDATE-c1.start_time)*60*60*24) || ')');
      DBMS_OUTPUT.PUT_LINE(CHR(9) || '  Total Commits for this Session: ' || c1.commits);
   END LOOP;

   ----------------------------------------------------
   -- TEMP Usage
   ----------------------------------------------------

   DBMS_OUTPUT.PUT_LINE('TEMP Usage  :');
   FOR c1 IN ( SELECT  sort.blocks*ts.block_size             total_bytes
                     , DECODE(sort.segtype,'DATA','DATA (Global Temp Table)',sort.segtype) segtype
                     , extents
               FROM    gv$sort_usage    sort
                     , dba_tablespaces ts
               WHERE   sort.session_addr = sess_details.saddr
               AND     sort.inst_id = sess_details.inst_id
               AND     ts.tablespace_name = sort.tablespace) LOOP
      DBMS_OUTPUT.PUT_LINE(CHR(9) || c1.segtype || ': ' || appdba_format_size(c1.total_bytes));
   END LOOP;

   ----------------------------------------------------
   -- Session Statistics
   ----------------------------------------------------

   DBMS_OUTPUT.PUT_LINE('Statistics  :');
   DBMS_OUTPUT.PUT_LINE(CHR(9));
   DBMS_OUTPUT.PUT_LINE(CHR(9) || 'STATISTIC                                                           VALUE');
   DBMS_OUTPUT.PUT_LINE(CHR(9) || '------------------------------------------------------------ ------------');
   FOR c1 IN ( SELECT  DECODE(n.name
                     , 'db block gets'
                        , 'db block gets (current value of block) UPDATE, etc.'
                     , 'consistent gets'
                        , 'consistent gets (read-consistent view of block) SELECT, etc.'
                     , 'consistent changes'
                        , 'consistent changes (undo records applied)'
                     , name)                                                     name
                     , s.value
               FROM    gv$sesstat   s
                     , gv$statname  n
               WHERE   n.name IN (  'db block gets'
                           , 'consistent gets'
                           , 'physical reads'
                           , 'db block changes'
                           , 'consistent changes'
                         -- Ora bug causes this value to exceed count from gv$open_cursor
                         --, 'opened cursors current'
                           , 'user commits'
                           , 'user rollbacks'
                           , 'redo entries'
               , 'cleanouts only - consistent read gets'
               , 'cleanouts and rollbacks - consistent read gets'
                           , 'session uga memory'
                           , 'session uga memory max'
                           , 'session pga memory'
                           , 'session pga memory max'
                           , 'table fetch continued row'
                           , 'sorts (memory)'
                           , 'sorts (disk)')
               AND     s.statistic# = n.statistic#
           AND     s.inst_id    = n.inst_id
               AND     s.sid        = sess_details.sid
           AND     s.inst_id    = sess_details.inst_id) LOOP
      IF c1.name LIKE 'session % memory%' THEN
         DBMS_OUTPUT.PUT_LINE(CHR(9) || RPAD(c1.name,60) || ' ' || LPAD(appdba_format_size(c1.value),12));
      ELSE
         DBMS_OUTPUT.PUT_LINE(CHR(9) || RPAD(c1.name,60) || ' ' || LPAD(TRIM(TO_CHAR(c1.value,'9,999,999,990')),12));
      END IF;
   END LOOP;

   ----------------------------------------------------
   -- Overall Session Waits / Events
   ----------------------------------------------------

   DBMS_OUTPUT.PUT_LINE(CHR(9));
   DBMS_OUTPUT.PUT_LINE(CHR(9) || 'EVENT                                    WAITS      AVG                      DURATION     PCT');
   DBMS_OUTPUT.PUT_LINE(CHR(9) || '--------------------------------- ------------ -------- ----------------------------- -------');
   FOR c1 IN ( SELECT event, waits, avg, secs, pct
               FROM (
                  SELECT  event
                        , waits
                        , avg                            avg
                        , secs                           secs
                        , (RATIO_TO_REPORT(secs) OVER ())*100 pct
                  FROM (
                     SELECT  e.event
                           , e.total_waits       waits
                           , e.time_waited/e.total_waits/100   avg
                           , e.time_waited/100   secs
                     FROM    gv$session_event  e
                     WHERE   e.sid     = sess_details.sid
                     AND     e.inst_id = sess_details.inst_id
                     UNION ALL
                     SELECT  n1.name                            event
                           , s2.value                           waits
                           , s2.value/GREATEST(s1.value,1)/100  avg
                           , s1.value/100                       secs
                     FROM    gv$statname n1
                           , gv$sesstat  s1
                           , gv$statname n2
                           , gv$sesstat  s2
                     WHERE   s1.sid     = sess_details.sid
                     AND     s1.inst_id = sess_details.inst_id
                     AND     s2.sid     = sess_details.sid
                     AND     s2.inst_id = sess_details.inst_id
                     AND     n1.statistic# = s1.statistic#
                     AND     n1.inst_id = sess_details.inst_id
                     AND     n2.statistic# = s2.statistic#
                     AND     n2.inst_id = sess_details.inst_id
                     AND     n1.name = 'CPU used by this session'
                     AND     n2.name = 'user calls'
                     /*UNION ALL
                     SELECT  'UNACCOUNTED FOR'                  event
                           , TO_NUMBER(NULL)                    waits
                           , TO_NUMBER(NULL)                    avg
                           , ((SYSDATE-sess_details.logon_time)*24*60*60) -
                             ((se.time_waited+ss.value)/100)    secs
                     FROM    (SELECT SUM(time_waited) time_waited
                              FROM   gv$session_event
                              WHERE  sid = sess_details.sid
                              AND    inst_id = sess_details.inst_id) se
                           , gv$sesstat ss
                           , gv$statname sn
                     WHERE   ss.sid        = sess_details.sid
                     AND     ss.inst_id    = sess_details.inst_id
                     AND     ss.statistic# = sn.statistic#
                     AND     sn.inst_id    = sess_details.inst_id
                     AND     sn.name       = 'CPU used by this session'*/
                     ORDER BY secs DESC)
                  )
               WHERE pct > 0.1) LOOP
      DBMS_OUTPUT.PUT_LINE(CHR(9) || RPAD(c1.event,35) || LPAD(NVL(TO_CHAR(c1.waits),'-'),11) ||
                LPAD(NVL(TO_CHAR(c1.avg,'9990.999'),'-'),9) ||
                LPAD(appdba_format_duration(c1.secs),30) || TO_CHAR(c1.pct,'9990.99') || '%');
   END LOOP;

END;
/
