-- Copyright 2018 Tanel Poder. All rights reserved. More info at http://tanelpoder.com
/*[[
    Find in which heap (UGA, PGA or Shared Pool) a memory address resides. Usage: @@NAME <addr>
    
    Refer to https://raw.githubusercontent.com/tanelpoder/tpt-oracle/master/fcha.sql
    
    Example:
    ========
    SQL> sys fcha 0000002B37FF94D8
    Find in which heap (UGA, PGA or Shared Pool) the memory address 0000002B37FF94D8 resides...

    WARNING!!! This script will query X$KSMSP, which will cause heavy shared pool latch contention
    in systems under load and with large shared pool. This may even completely hang
    your instance until the query has finished! You probably do not want to run this in production!

    INST_ID LOC     KSMCHPTR     KSMCHIDX KSMCHDUR KSMCHCOM KSMCHSIZ KSMCHCLS KSMCHTYP KSMCHPAR
    ------- --- ---------------- -------- -------- -------- -------- -------- -------- --------
          4 SGA 0000002B37FF94D8        7        1 KLCS        27392 freeabl         0 00
          2 SGA 0000002B37FF94D8        1        1 KLCS        27392 freeabl         0 00
          3 SGA 0000002B37FF94D8        1        1 KLCS        27392 freeabl         0 00
          1 SGA 0000002B37FF94D8        7        1 KLCS        27392 freeabl         0 00
    
    --[[
        @ARGS: 1
    --]]
]]*/


-- Licensed under the Apache License, Version 2.0. See LICENSE.txt for terms & conditions.

--------------------------------------------------------------------------------
--
-- File name:   fcha.sql (Find CHunk Address) v0.2
-- Purpose:     Find in which heap (UGA, PGA or Shared Pool) a memory address resides
--              
-- Author:      Tanel Poder
-- Copyright:   (c) http://blog.tanelpoder.com | @tanelpoder
--              
-- Usage:       @fcha <addr_hex>
--              @fcha F6A14448
--
-- Other:       This would only report an UGA/PGA chunk address if it belongs
--              to *your* process/session (x$ksmup and x$ksmpp do not see other
--              session/process memory)
--              
--------------------------------------------------------------------------------

prompt Find in which heap (UGA, PGA or Shared Pool) the memory address &V1 resides...
prompt
prompt WARNING!!! This script will query X$KSMSP, which will cause heavy shared pool latch contention 
prompt in systems under load and with large shared pool. This may even completely hang 
prompt your instance until the query has finished! You probably do not want to run this in production!
prompt

SELECT * FROM TABLE(GV$(CURSOR(
    SELECT /*+PQ_CONCURRENT_UNION*/ userenv('instance') inst_id,a.* 
    FROM (
        SELECT 'SGA' LOC, KSMCHPTR, KSMCHIDX, KSMCHDUR, KSMCHCOM, KSMCHSIZ, KSMCHCLS, KSMCHTYP, KSMCHPAR
        FROM   sys.x$ksmsp
        WHERE  to_number(substr('&V1', instr(lower('&V1'), 'x') + 1), 'XXXXXXXXXXXXXXXX') BETWEEN
               to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') AND to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1
        UNION ALL
        SELECT 'UGA', KSMCHPTR, NULL, NULL, KSMCHCOM, KSMCHSIZ, KSMCHCLS, KSMCHTYP, KSMCHPAR
        FROM   sys.x$ksmup
        WHERE  to_number(substr('&V1', instr(lower('&V1'), 'x') + 1), 'XXXXXXXXXXXXXXXX') BETWEEN
               to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') AND to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1
        UNION ALL
        SELECT 'PGA', KSMCHPTR, NULL, NULL, KSMCHCOM, KSMCHSIZ, KSMCHCLS, KSMCHTYP, KSMCHPAR
        FROM   sys.x$ksmpp
        WHERE  to_number(substr('&V1', instr(lower('&V1'), 'x') + 1), 'XXXXXXXXXXXXXXXX') BETWEEN
               to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') AND to_number(ksmchptr, 'XXXXXXXXXXXXXXXX') + ksmchsiz - 1
    ) A
)));