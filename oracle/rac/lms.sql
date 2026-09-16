/*[[
    Show LMS stats
    ==============
    Show the LMS process related stats of the instance: the CR/current block server counters, the
    gc cr/current block receive time with the lost blocks, and the gv$process/gv$session details
    of the LMS processes. Usage: @@NAME

    Notes:
    ------
    - the 1st and 2nd block are printed in pivot mode(pivot=20), the 3rd one converts the
      centisecond time to us(*1e4) so that it can use the duration format usmhd2
    - ADDR/PROGRAM/TRACEID/TRACEFILE/SOSID/TERMINAL/PGA_* columns of gv$process are hidden
      by 'COL ... NOPRINT'
    - an empty result is normal on a single instance, where the gc counters stay 0
]]*/
SET sep4k on pivotsort head
COL addr,program,traceid,tracefile,sosid,terminal,username,serial#,background,con_id,numa_default,pga_alloc_mem NOPRINT
COL "cr time,cur time,avg cr time,avg cur time,waited,cpu_used" FOR usmhd2
COL pga_used_mem,pga_freeable_mem,pga_max_mem FOR kmg2

grid {
    [[SELECT /*grid={topic='gv$cr_block_server',pivot=20}*/ * FROM gv$cr_block_server ORDER BY inst_id]],
    '|',
    [[SELECT /*grid={topic='gv$current_block_server',pivot=20}*/ * FROM gv$current_block_server ORDER BY inst_id]],
    '|',
    [[SELECT /*grid={topic='GC CR/CUR Block time'}*/
             b1.inst_id INT,
             b2.value "CR Blocks",
             ((b1.value / nullif(b2.value, 0)) * 1e4) "Avg CR Time",
             b4.value "CUR Blocks",
             ((b3.value / nullif(b4.value, 0)) * 1e4) "Avg CUR Time",
             b5.value "Losts"
        FROM gv$sysstat b1,
             gv$sysstat b2,
             gv$sysstat b3,
             gv$sysstat b4,
             gv$sysstat b5
       WHERE b1.name = 'gc cr block receive time'
         AND b2.name = 'gc cr blocks received'
         AND b3.name = 'gc current block receive time'
         AND b4.name = 'gc current blocks received'
         AND b5.name = 'gc blocks lost'
         AND b1.inst_id = b2.inst_id
         AND b1.inst_id = b3.inst_id
         AND b1.inst_id = b4.inst_id
         AND b1.inst_id = b5.inst_id
       ORDER BY 1]],
    '-',
    [[SELECT /*grid={topic='gv$process'}*/
             a.*,
             nvl(b.status, 'Idle') status,
             b.wait_time_micro waited,
             b.sid || ',' || b.serial# session#,
             b.event
        FROM gv$process a
        LEFT JOIN gv$session b
        ON   (a.addr = b.paddr AND a.inst_id = b.inst_id)
       WHERE background > 0
         AND pname LIKE 'LMS%'
       ORDER BY a.inst_id, pname]]
}
