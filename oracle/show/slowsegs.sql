/*[[Show slow segments(Doc ID 1491748.1)]]*/

col bytes for kmg2
COL blocks,extents FOR TMB2
PRO Use "dbms_space_admin.tablespace_fix_segment_extblks(<tbs_name>)" to correct slow segments
PRO ==========================================================================================
SELECT NVL(tbs_name, '- TOTAL -') tbs_name,
       TBSTYPE,
       NVL(owner, '- TOTAL -') owner,
       segment_name,
       TYPE,
       segs,
       bytes,
       blocks,
       extents
FROM   (SELECT tablespace_name tbs_name,
               owner,
               segment_name,
               regexp_substr(segment_type, '\S+') TYPE,
               SEGMENT_SUBTYPE TBSTYPE,
               COUNT(1) segs,
               SUM(bytes) bytes,
               SUM(blocks) blocks,
               SUM(extents) extents,
               grouping_id(tablespace_name, owner) grp
        FROM   sys.sys_dba_segs
        WHERE  bitand(segment_flags, 131073) = 1
        AND    segment_type NOT IN ('ROLLBACK', 'DEFERRED ROLLBACK', 'TYPE2 UNDO')
        AND    tablespace_name NOT IN ('SYSTEM')
        GROUP  BY ROLLUP((tablespace_name,SEGMENT_SUBTYPE), (owner, segment_name,regexp_substr(segment_type, '\S+'))))
ORDER  BY grp,2,3,4;
