/*[[show LMS stats]]*/
set sep4k on pivotsort head
col program,traceid,tracefile,sosid,terminal,USERNAME,SERIAL#,BACKGROUND noprint
col "CR Time,CUR Time,Avg CR Time,Avg CUR Time" for usmhd2

grid {
    [[select /*grid={topic='gv$cr_block_server',pivot=20}*/ * from gv$cr_block_server order by inst_id]],
    '|',
    [[select /*grid={topic='gv$current_block_server',pivot=20}*/ * from gv$current_block_server order by inst_id]],
    '|',
    [[SELECT /*grid={topic='GC CR/CUR Block time'}*/
            B1.INST_ID INT,
            B2.VALUE "CR Blocks",
            ((B1.VALUE/nullif(B2.VALUE,0) ) *1e4) "Avg CR Time",
            B4.VALUE "CUR Blocks",
            ((B3.VALUE/nullif(B4.VALUE,0) ) *1e4) "Avg CUR Time",
            B5.VALUE "Losts"
        FROM GV$SYSSTAT B1,
             GV$SYSSTAT B2,
             GV$SYSSTAT B3,
             GV$SYSSTAT B4,
             GV$SYSSTAT B5
        WHERE B1.NAME = 'gc cr block receive time'
        AND B2.NAME = 'gc cr blocks received'
        AND B3.NAME = 'gc current block receive time'
        AND B4.NAME = 'gc current blocks received'
        AND B5.NAME = 'gc blocks lost'
        AND B1.INST_ID = B2.INST_ID
        AND B1.INST_ID = B3.INST_ID
        AND B1.INST_ID = B4.INST_ID
        AND B1.INST_ID = B5.INST_ID
        ORDER BY 1]],
    '-',
    [[select /*grid={topic='gv$process'}*/  * from gv$process where background>0 and pname like 'LMS%' order by inst_id,pname]]
}