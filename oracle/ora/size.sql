/*[[
    Show object size. Usage: ora size [-d] [ [owner.]object_name[.PARTITION_NAME] ]  
    If not specify the parameter, then list the top 100 segments within current schema. and option '-d' used to detail in segment level, otherwise in name level
    --[[
        @CHECK_ACCESS: sys.seg$={}
        &OPT:  default={1}, d={2}
        &OPT2: default={}, d={subobject_name,object_id,data_object_id,}
        &OPT3: default={}, d={o.subname,}
    --]]
]]*/
set feed off
VAR cur REFCURSOR
BEGIN
    IF :V1 IS NOT NULL THEN
        OPEN :cur FOR
        WITH r AS
         (SELECT DISTINCT owner, object_name, object_type,null partition_name
          FROM   dba_objects
          WHERE  owner = nvl(upper(TRIM(SUBSTR(:V1, 1, INSTR(:V1, '.') - 1))),SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'))
          AND    object_name = UPPER(DECODE(INSTR(:V1, '.'), 0, :V1, regexp_substr(:V1, '[^ \.]+', 1, 2)))
          AND    subobject_name IS NULL
          AND    SUBSTR(object_type, 1, 3) IN ('TAB', 'IND', 'LOB')
          AND    :V1 IS NOT NULL
          UNION ALL
          SELECT DISTINCT owner, object_name, object_type,subobject_name
          FROM   dba_objects
          WHERE  owner = UPPER(DECODE(LENGTH(:V1)-LENGTH(REPLACE(:V1,'.')),2,regexp_substr(:V1, '[^ \.]+'),SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')))
          AND    object_name = UPPER(regexp_substr(:V1, '[^ \.]+',1,LENGTH(:V1)-LENGTH(REPLACE(:V1,'.'))))
          AND    subobject_name=UPPER(regexp_substr(:V1, '[^ \.]+',1,LENGTH(:V1)-LENGTH(REPLACE(:V1,'.'))+1))
          AND    SUBSTR(object_type, 1, 3) IN ('TAB', 'IND', 'LOB')
          AND    INSTR(:V1,'.')>0),
        R2 AS
         (SELECT /*+materialize*/a.*,max(p) over()||'%' PARTITION_NAME
          FROM   (SELECT 1 flag, owner, index_name object_name, 'INDEX' object_type,null p,
                         (SELECT SUM(1 + avg_col_len * (1 - nvl(y.num_nulls,0)/greatest(a.num_rows,1)))+ DECODE(A.Uniqueness,'UNIQUE',0,1) +DECODE(MAX(LOCALITY), 'GLOBAL', 10, 6)
                           FROM   Dba_Ind_Columns x, Dba_Tab_Cols y,Dba_Part_Indexes I
                           WHERE  x.table_owner = y.owner
                           AND    x.table_name = y.table_name
                           AND    x.column_name = y.column_name
                           AND    a.owner = x.index_owner
                           AND    a.index_name = x.index_name
                           AND    i.owner = a.owner
                           AND    I.index_name = a.index_name) col_len
                   FROM   Dba_Indexes a
                   WHERE  (table_owner, table_name) IN (SELECT owner, object_name FROM r)
                   UNION
                   SELECT 2 flag, owner, segment_name, 'LOB' object_type,null,null
                   FROM   Dba_lobs
                   WHERE  (owner, table_name) IN (SELECT owner, object_name FROM r)
                   UNION
                   SELECT 0 flag, owner, object_name, object_type,partition_name,null
                   FROM   r) a),
        objs AS
         (SELECT decode(bitand(t.property, 8192), 8192, 'NESTED TABLE', 'TABLE') typ#, t.obj#, t.ts#, rowcnt,
                 'ROWS' cnt_unit,avgrln cnt,pctfree$ pct,initrans
          FROM   sys.tab$ t
          WHERE  bitand(t.property, 1024) = 0 
          UNION ALL
          SELECT 'TABLE PARTITION', tp.obj#, tp.ts#, rowcnt, 'ROWS',avgrln,pctfree$,initrans
          FROM   sys.tabpart$ tp
          UNION ALL
          SELECT 'TABLE SUBPARTITION', tsp.obj#, tsp.ts#, rowcnt, 'ROWS',avgrln,pctfree$,initrans
          FROM   sys.tabsubpart$ tsp
          UNION ALL
          SELECT decode(i.type#, 8, 'LOBINDEX', 'INDEX'), i.obj#, i.ts#, leafcnt, 'LEAVES',rowcnt,pctfree$,initrans
          FROM   sys.ind$ i
          WHERE  i.type# IN (1, 2, 3, 4, 6, 7, 8, 9)
          UNION ALL
          SELECT 'INDEX PARTITION', ip.obj#, ip.ts#, leafcnt, 'LEAVES',rowcnt,pctfree$,initrans
          FROM   sys.indpart$ ip
          UNION ALL
          SELECT 'INDEX SUBPARTITION', isp.obj#, isp.ts#, leafcnt, 'LEAVES',rowcnt,pctfree$,initrans
          FROM   sys.indsubpart$ isp
          UNION ALL
          SELECT 'LOBSEGMENT', l.lobj#, l.ts#,chunk,'CHUNK',NULL,NULL,NULL
          FROM   sys.lob$ l
          WHERE  (bitand(l.property, 64) = 0)
          OR     (bitand(l.property, 128) = 128)
          UNION ALL
          SELECT decode(lf.fragtype$, 'P', 'LOB PARTITION', 'LOB SUBPARTITION'), lf.fragobj#, lf.ts#,NULL,NULL,NULL,NULL,NULL
          FROM   sys.lobfrag$ lf
          UNION ALL
          SELECT 'CLUSTER', c.obj#, c.ts#, SIZE$, 'KEY_SIZE',NULL,pctfree$,initrans
          FROM   sys.clu$ c)
        SELECT /*+ordered use_nl(r2 u o so ts) push_pred(so) use_hash(s)*/
             r2.owner, r2.object_name, r2.object_type,&OPT3
             round(sum(s.blocks * ts.blocksize)/1024/1024,2) size_mb,
             round(sum(s.blocks * ts.blocksize)/1024/1024/1024,3) size_gb,
             COUNT(1) segments,
             SUM(s.extents) extents,
             ROUND(AVG(s.blocks * ts.blocksize)/1024) init_ext_kb,
             ROUND(AVG(s.extsize * ts.blocksize)/1024) next_extent_kb,
             MAX(ts.name) KEEP(dense_rank LAST ORDER BY s.blocks) tablespace_name,
             SUM(rowcnt) cnt_stat,
             cnt_unit,
             round(sum(ts.blocksize*greatest(ts.dflinit,1.2*
                case r2.object_type 
                     WHEN 'TABLE' then--11 = 3 * ub1 + sb2*2 +ub4, 24=kbbit 
                        rowcnt*greatest(11,cnt)/ceil((ts.blocksize-(so.initrans-1)*24)*(1-so.pct/100))
                     WHEN 'INDEX' then
                        so.cnt/floor((ts.blocksize - 113 - 23 * so.initrans) / (1 - so.pct / 100)/r2.col_len)
                 END
             ))/1024/1024,2) est_size_mb --Estimated size highly depends on statistics(both global and partition level)
        FROM   R2, sys.user$ u, sys.obj$ o, objs so, sys.ts$ ts, sys.seg$ s
        WHERE  o.owner# = u.user#
        AND    o.obj# = so.obj#
        AND    u.name = R2.owner
        AND    o.name = r2.object_name
        AND    so.ts# = ts.ts#
        AND    s.hwmincr=o.dataobj#
        AND    o.owner# = u.user#
        AND    nvl(o.subname,' ') like r2.partition_name
        GROUP BY r2.owner, r2.object_name,r2.object_type,&OPT3 cnt_unit
        ORDER BY SIZE_MB DESC;
    ELSE
        OPEN :CUR FOR
        SELECT rownum "#",a.*
        FROM   (SELECT /*+ordered use_hash(@sel$3 o) use_hash(@sel$5 o) use_hash(o s ts) no_merge(o) push_subq(o) swap_join_inputs(ts)*/
                  o.object_name,&OPT2  decode(&opt,1,regexp_substr(object_type, '\S+'),object_type) object_type,
                  round(SUM(s.blocks * ts.blocksize) / 1024 / 1024, 2) size_mb, 
                  round(SUM(s.blocks * ts.blocksize) / 1024 / 1024/1024, 3) size_gb, 
                  COUNT(1) segments,
                  SUM(s.extents) extents, ROUND(AVG(s.blocks * ts.blocksize) / 1024) init_ext_kb,
                  ROUND(AVG(s.extsize * ts.blocksize) / 1024) next_extent_kb,
                  MAX(ts.name) KEEP(dense_rank LAST ORDER BY s.blocks) tablespace_name
                 FROM   dba_objects o, sys.seg$ s, sys.ts$ ts
                 WHERE  s.hwmincr = o.data_object_id
                 AND    s.ts# = ts.ts#
                 AND    o.owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                 AND    o.data_object_id IS NOT NULL
                 GROUP  BY o.object_name,&OPT2  decode(&opt,1,regexp_substr(object_type, '\S+'),object_type)
                 ORDER  BY size_mb DESC) a
        WHERE  ROWNUM <= 100;
    END IF;
END;
/
