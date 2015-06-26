/*[[ Show object size. Usage: ora size [ [owner.]object_name[.PARTITION_NAME] ]  ]]*/
set feed off
VAR cur CURSOR
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
          FROM   (SELECT 1 flag, owner, index_name object_name, 'INDEX' object_type,null p
                   FROM   Dba_Indexes
                   WHERE  (table_owner, table_name) IN (SELECT owner, object_name FROM r)
                   UNION
                   SELECT 2 flag, owner, segment_name, 'LOB' object_type,null
                   FROM   Dba_lobs
                   WHERE  (owner, table_name) IN (SELECT owner, object_name FROM r)
                   UNION
                   SELECT 0 flag, owner, object_name, object_type,partition_name
                   FROM   r) a)
        SELECT owner, object_name, object_type,
               0+REGEXP_SUBSTR(INFO,'[^/]+',1,1) "SIZE(MB)",
               0+REGEXP_SUBSTR(INFO,'[^/]+',1,2) SEGMENTS,
               0+REGEXP_SUBSTR(INFO,'[^/]+',1,3) EXTENTS,
               0+REGEXP_SUBSTR(INFO,'[^/]+',1,4) AVG_INIT_KB,
                 REGEXP_SUBSTR(INFO,'[^/]+',1,5) TABLESPACE_NAME
        FROM(
            SELECT R2.*,
                   (SELECT round(SUM(bytes) / 1024 / 1024, 2)||'/'||count(1)||'/'||SUM(EXTENTS)||'/'||ROUND(AVG(INITIAL_EXTENT)/1024)||'/'||MAX(TABLESPACE_NAME) KEEP(DENSE_RANK LAST ORDER BY BYTES)
                     FROM   dba_segments s
                     WHERE  r2.owner = s.owner
                     AND    r2.object_name = s.segment_name
                     AND    NVL(s.PARTITION_NAME,' ') LIKE R2.PARTITION_NAME) INFO
            FROM   R2)
        ORDER  BY flag, owner,object_name;
    ELSE
        OPEN :CUR FOR
        SELECT * FROM (
            SELECT OWNER,SEGMENT_NAME,round(SUM(bytes) / 1024 / 1024, 2) "SIZE(MB)" , count(1) SEGMENTS, SUM(EXTENTS) EXTENTS, ROUND(AVG(INITIAL_EXTENT)/1024) AVG_INIT_KB,
                    MAX(TABLESPACE_NAME) KEEP(DENSE_RANK LAST ORDER BY BYTES) TABLESPACE_NAME
            FROM   dba_segments s
            WHERE  OWNER=SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
            GROUP BY OWNER,SEGMENT_NAME
            ORDER BY 3 DESC
        ) WHERE ROWNUM<=100;
    END IF;
END;
/
/*,
--estimation of object size: refer to https://docs.oracle.com/cd/A58617_01/server.804/a58397/apa.htm
HDR AS
 (SELECT --+materialize  
          MAX(a.VALUE) - SUM(CASE
                                WHEN B.TYPE IN ('KCBH', 'UB4', 'KTBBH', 'KDBH') THEN
                                 B.TYPE_SIZE
                            END) HZ1,
         MAX(DECODE(b.type, 'KTBIT', type_size)) KTBIT,
         MAX(DECODE(b.type, 'KDBT', type_size)) KDBT,
         MAX(DECODE(b.type, 'UB1', type_size)) UB1,
         MAX(DECODE(b.type, 'UB4', type_size)) UB4,
         MAX(DECODE(b.type, 'SB2', type_size)) SB2,
         MAX(a.VALUE) block_size
  FROM   v$parameter a, v$type_size b
  WHERE  NAME = 'db_block_size'
  AND    b.TYPE IN ('KCBH', 'UB4', 'KTBBH', 'KDBH', 'KTBIT', 'KDBT', 'UB1', 'SB2')),
  r3 AS (SELECT --+materialize  
   * FROM
 (SELECT r2.*,--Non-partition table
         num_rows / FLOOR(GREATEST(ceil(ds),3 * ub1 + sb2*2 +ub4)/greatest(avg_row_len,1)) est_block
  FROM   (select a.*,nvl((HZ1 - (a.INI_TRANS - 1) * KTBIT) * (1 - a.PCT_FREE / 100),(
             select 0.8*MIN((HZ1 - (c.INI_TRANS - 1) * KTBIT) * (1 - c.PCT_FREE / 100))
             from   dba_tab_partitions c
             WHERE  c.table_name = a.table_name
             AND    c.table_owner = a.owner  
         )) ds from dba_tables a, hdr) a, r2, hdr
  WHERE  a.table_name = r2.segment_name
  AND    a.owner = r2.owner  
  UNION ALL
  SELECT r2.*,--Non-partition index
         1.1 * z.num_rows / floor(ds /
         ((SELECT SUM(1 + AVG_col_len * (1 - y.NUM_NULLS / nullif(z.num_rows,0)))
           FROM   Dba_Ind_Columns x, Dba_Tab_Cols y
           WHERE  x.table_owner = y.owner
           AND    x.table_name = y.table_name
           AND    x.column_name = y.column_name
           AND    a.owner = x.index_owner
           AND    a.index_name = x.index_name) + DECODE(A.Uniqueness,'UNIQUE1',0,2) +
         (SELECT DECODE(MAX(LOCALITY), 'GLOBAL', 10, 6)
           FROM   Dba_Part_Indexes I
           WHERE  i.owner = r2.owner
           AND    I.index_name = r2.segment_name))) c
  FROM   HDR, (select a.*,nvl((block_size - 113 - 23 * a.INI_TRANS) / (1 - a.pct_free / 100),
                      0.8*(select MIN((block_size - 113 - 23 * c.INI_TRANS) / (1 - c.pct_free / 100))
                       from   dba_ind_partitions c
                       where  c.INDEX_NAME = A.index_name
                       AND    c.INDEX_OWNER = a.owner)) ds
               from dba_indexes a,hdr) a, Dba_Tables z, R2
  WHERE  a.INDEX_name = r2.segment_name
  AND    a.owner = r2.owner
  AND    a.table_owner = z.owner
  AND    a.table_name = z.table_name))*/