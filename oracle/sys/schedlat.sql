/*[[
 Show CPU scheduling latency by monitoring PSP0 process. Usage: @@NAME [<bucket size(in minute)>]

 Copyright 2020 Tanel Poder. All rights reserved. More info at https://tanelpoder.com
 Licensed under the Apache License, Version 2.0. See LICENSE.txt for terms and conditions.

 Name:    schedlat.sql
 Purpose: List PSP0 process scheduling latency test results (where scheduling latency is not 0)
 Other:   Oracle 12c+ PSP0 process regularly (voluntarily) goes to sleep for 1000 microseconds
          taking a high resolution system timestamp just before going to sleep and right after
          getting back onto CPU. Usin these timestamps it checks if it managed to wake up 
          "exactly" 1000 usec later or

]]*/
COL avg_latency,max_latency,sched_delay_micro for usmhd2
COL BUCKET# BREAK SKIP -
SET FEED OFF
PROMPT Listing recent non-zero scheduling delays from PSP0 process
PROMPT ===========================================================
SELECT *
FROM   (SELECT *
        FROM   TABLE(GV$(CURSOR(
        	    SELECT userenv('instance') inst, sample_start_time, sample_end_time, sched_delay_micro sched_delay
                FROM   sys.x$kso_sched_delay_history
                WHERE  sched_delay_micro != 0)))
        ORDER  BY 2 DESC)
WHERE  ROWNUM <= 30;

PROMPT Any noticed scheduling delays during recent 5 buckets
PROMPT =====================================================
SELECT *
FROM   TABLE(GV$(CURSOR (
          SELECT ROW_NUMBER() OVER(ORDER BY FLOOR(1440*(SYSDATE-sample_start_time)/NVL(0+regexp_substr(:V1,'^\d+$'),5))) BUCKET#,
          		 userenv('instance') inst,
                 MIN(sample_start_time) history_begin_time,
                 MAX(sample_end_time) history_end_time,
                 MAX(sched_delay_micro) max_latency,
                 AVG(sched_delay_micro) avg_latency,
                 COUNT(1) Samples
          FROM   sys.x$kso_sched_delay_history
          GROUP  BY FLOOR(1440*(SYSDATE-sample_start_time)/NVL(0+regexp_substr(:V1,'^\d+$'),5))
        )))
WHERE BUCKET#<=5
ORDER  BY 1,2;