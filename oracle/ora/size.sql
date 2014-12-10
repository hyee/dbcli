/*[[
Show object size. Usage: ora size object_name [owner]
]]*/

--estimation of object size: refer to https://docs.oracle.com/cd/A58617_01/server.804/a58397/apa.htm
WITH r AS
 (SELECT DISTINCT owner, segment_name
  FROM   Dba_Segments
  WHERE  upper(owner || '.' || segment_name) LIKE upper('%' || :V2 || '.' || :V1)),
R2 AS
 (SELECT owner, index_name segment_name, table_owner, table_name
  FROM   Dba_Indexes
  WHERE  (table_owner, table_name) IN (SELECT * FROM r)
  UNION
  SELECT owner, segment_name, owner, table_name
  FROM   Dba_lobs
  WHERE  (owner, table_name) IN (SELECT * FROM r)
  UNION
  SELECT r.*, r.*
  FROM   r),
HDR AS
 (SELECT /*+materialize*/ MAX(a.VALUE) - SUM(CASE
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
r3 AS (SELECT /*+materialize*/  * FROM
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
  AND    a.table_name = z.table_name
  ))
SELECT owner,
       NVL(segment_name, '--TOTAL--') segment_name,
       MAX(segment_type) segment_type,
       round(SUM(bytes / 1024 / 1024), 2) "Size(MB)",
       round(SUM(DISTINCT block_size*est_block / 1024 / 1024), 2) "Est Size(MB)",
       trunc(AVG(INITIAL_EXTENT)) INIEXT,
       MAX(max_extents) MAXEXT
FROM   Dba_Segments S
JOIN   r2
USING  (owner, segment_name)
LEFT JOIN   r3
USING  (owner, segment_name, table_owner, table_name)
CROSS  JOIN hdr
GROUP  BY GROUPING SETS((owner, segment_name, table_owner, table_name),(table_owner, table_name))
