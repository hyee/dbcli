@@&&edb360_0g.tkprof.sql
DEF section_id = '2b';
DEF section_name = 'Storage';
EXEC DBMS_APPLICATION_INFO.SET_MODULE('&&edb360_prefix.','&&section_id.');
SPO &&edb360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

DEF title = 'Tablespace';
DEF main_table = 'V$TABLESPACE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$tablespace
 ORDER BY
       ts#
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tablespaces';
DEF main_table = 'DBA_TABLESPACES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tablespaces
 ORDER BY
       tablespace_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tablespace Groups';
DEF main_table = 'DBA_TABLESPACE_GROUPS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_tablespace_groups
 ORDER BY
       group_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tablespace Usage';
DEF main_table = 'DBA_SEGMENTS';
COL pct_used FOR 999990.0;
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
WITH
files AS (
SELECT /*+ &&sq_fact_hints. */
       tablespace_name,
       SUM(DECODE(autoextensible, ''YES'', maxbytes, bytes)) / 1024 / 1024 / 1024 total_gb
  FROM dba_data_files
 GROUP BY
       tablespace_name
),
segments AS (
SELECT /*+ &&sq_fact_hints. */
       tablespace_name,
       SUM(bytes) / 1024 / 1024 / 1024 used_gb
  FROM dba_segments
 GROUP BY
       tablespace_name
),
tablespaces AS (
SELECT /*+ &&sq_fact_hints. */
       files.tablespace_name,
       ROUND(files.total_gb, 1) total_gb,
       ROUND(segments.used_gb, 1) used_gb,
       ROUND(100 * segments.used_gb / files.total_gb, 1) pct_used
  FROM files,
       segments
 WHERE files.total_gb > 0
   AND files.tablespace_name = segments.tablespace_name(+)
 ORDER BY
       files.tablespace_name
),
total AS (
SELECT /*+ &&sq_fact_hints. */
       ''Total'' tablespace_name,
       SUM(total_gb) total_gb,
       SUM(used_gb) used_gb,
       ROUND(100 * SUM(used_gb) / SUM(total_gb), 1) pct_used
  FROM tablespaces
)
SELECT tablespace_name,
       total_gb,
       used_gb,
       pct_used
  FROM tablespaces 
 UNION ALL
SELECT tablespace_name,
       total_gb,
       used_gb,
       pct_used
  FROM total 
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Datafile';
DEF main_table = 'V$DATAFILE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$datafile
 ORDER BY
       file#
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Data Files';
DEF main_table = 'DBA_DATA_FILES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_data_files
 ORDER BY
       file_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Data Files Usage';
DEF main_table = 'DBA_DATA_FILES';
COL pct_used FOR 999990.0;
COL pct_free FOR 999990.0;
BEGIN
  :sql_text := '
WITH
alloc AS (
SELECT /*+ &&sq_fact_hints. */
       tablespace_name,
       COUNT(*) datafiles,
       ROUND(SUM(bytes)/1024/1024/1024) gb
  FROM dba_data_files
 GROUP BY
       tablespace_name
),
free AS (
SELECT /*+ &&sq_fact_hints. */
       tablespace_name,
       ROUND(SUM(bytes)/1024/1024/1024) gb
  FROM dba_free_space
 GROUP BY
       tablespace_name
),
tablespaces AS (
SELECT /*+ &&sq_fact_hints. */
       a.tablespace_name,
       a.datafiles,
       a.gb alloc_gb,
       (a.gb - f.gb) used_gb,
       f.gb free_gb
  FROM alloc a, free f
 WHERE a.tablespace_name = f.tablespace_name
 ORDER BY
       a.tablespace_name
),
total AS (
SELECT /*+ &&sq_fact_hints. */
       SUM(alloc_gb) alloc_gb,
       SUM(used_gb) used_gb,
       SUM(free_gb) free_gb
  FROM tablespaces
)
SELECT v.tablespace_name,
       v.datafiles,
       v.alloc_gb,
       v.used_gb,
       CASE WHEN v.alloc_gb > 0 THEN
       LPAD(TRIM(TO_CHAR(ROUND(100 * v.used_gb / v.alloc_gb, 1), ''990.0'')), 8)
       END pct_used,
       v.free_gb,
       CASE WHEN v.alloc_gb > 0 THEN
       LPAD(TRIM(TO_CHAR(ROUND(100 * v.free_gb / v.alloc_gb, 1), ''990.0'')), 8)
       END pct_free
  FROM (
SELECT tablespace_name,
       datafiles,
       alloc_gb,
       used_gb,
       free_gb
  FROM tablespaces
 UNION ALL
SELECT ''Total'' tablespace_name,
       TO_NUMBER(NULL) datafiles,
       alloc_gb,
       used_gb,
       free_gb
  FROM total
) v
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tempfile';
DEF main_table = 'V$TEMPFILE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$tempfile
 ORDER BY
       file#
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Temp Files';
DEF main_table = 'DBA_TEMP_FILES';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_temp_files
 ORDER BY
       file_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'I/O Statistics for DB Files';
DEF main_table = 'V$IOSTAT_FILE';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$iostat_file
 ORDER BY
       1
';
END;
/
@@&&skip_10g.edb360_9a_pre_one.sql

DEF title = 'SYSAUX Occupants';
DEF main_table = 'V$SYSAUX_OCCUPANTS';
BEGIN
  :sql_text := '
SELECT /*+ &&top_level_hints. */
       *
  FROM v$sysaux_occupants
 ORDER BY
       1
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Database Growth per Month';
DEF main_table = 'V$DATAFILE';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */
       TO_CHAR(creation_time, ''YYYY-MM''),
       ROUND(SUM(bytes)/1024/1024) mb_growth,
       ROUND(SUM(bytes)/1024/1024/1024) gb_growth,
       ROUND(SUM(bytes)/1024/1024/1024/1024, 1) tb_growth
  FROM v$datafile
 GROUP BY
       TO_CHAR(creation_time, ''YYYY-MM'')
 ORDER BY
       TO_CHAR(creation_time, ''YYYY-MM'')
';
END;
/
@@edb360_9a_pre_one.sql
    
DEF title = 'Largest 200 Objects';
DEF main_table = 'DBA_SEGMENTS';
COL gb FOR 999990.000;
BEGIN
  :sql_text := '
WITH schema_object AS (
SELECT /*+ &&sq_fact_hints. */
       segment_type,
       owner,
       segment_name,
       tablespace_name,
       COUNT(*) segments,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(bytes) bytes
  FROM dba_segments
 GROUP BY
       segment_type,
       owner,
       segment_name,
       tablespace_name
), totals AS (
SELECT /*+ &&sq_fact_hints. */
       SUM(segments) segments,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(bytes) bytes
  FROM schema_object
), top_200_pre AS (
SELECT /*+ &&sq_fact_hints. */
       ROWNUM rank, v1.*
       FROM (
SELECT so.segment_type,
       so.owner,
       so.segment_name,
       so.tablespace_name,
       so.segments,
       so.extents,
       so.blocks,
       so.bytes,
       ROUND((so.segments / t.segments) * 100, 3) segments_perc,
       ROUND((so.extents / t.extents) * 100, 3) extents_perc,
       ROUND((so.blocks / t.blocks) * 100, 3) blocks_perc,
       ROUND((so.bytes / t.bytes) * 100, 3) bytes_perc
  FROM schema_object so,
       totals t
 ORDER BY
       bytes_perc DESC NULLS LAST
) v1
 WHERE ROWNUM < 201
), top_200 AS (
SELECT p.*,
       (SELECT SUM(p2.bytes_perc) FROM top_200_pre p2 WHERE p2.rank <= p.rank) bytes_perc_cum
  FROM top_200_pre p
), top_200_totals AS (
SELECT /*+ &&sq_fact_hints. */
       SUM(segments) segments,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(bytes) bytes,
       SUM(segments_perc) segments_perc,
       SUM(extents_perc) extents_perc,
       SUM(blocks_perc) blocks_perc,
       SUM(bytes_perc) bytes_perc
  FROM top_200
), top_100_totals AS (
SELECT /*+ &&sq_fact_hints. */
       SUM(segments) segments,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(bytes) bytes,
       SUM(segments_perc) segments_perc,
       SUM(extents_perc) extents_perc,
       SUM(blocks_perc) blocks_perc,
       SUM(bytes_perc) bytes_perc
  FROM top_200
 WHERE rank < 101
), top_20_totals AS (
SELECT /*+ &&sq_fact_hints. */
       SUM(segments) segments,
       SUM(extents) extents,
       SUM(blocks) blocks,
       SUM(bytes) bytes,
       SUM(segments_perc) segments_perc,
       SUM(extents_perc) extents_perc,
       SUM(blocks_perc) blocks_perc,
       SUM(bytes_perc) bytes_perc
  FROM top_200
 WHERE rank < 21
)
SELECT v.rank,
       v.segment_type,
       v.owner,
       v.segment_name,
       v.tablespace_name,
       CASE
       WHEN v.segment_type LIKE ''INDEX%'' THEN
         (SELECT i.table_name
            FROM dba_indexes i
           WHERE i.owner = v.owner AND i.index_name = v.segment_name)       
       WHEN v.segment_type LIKE ''LOB%'' THEN
         (SELECT l.table_name
            FROM dba_lobs l
           WHERE l.owner = v.owner AND l.segment_name = v.segment_name)
       END table_name,
       v.segments,
       v.extents,
       v.blocks,
       v.bytes,
       ROUND(v.bytes / 1024 / 1024 / 1024, 3) gb,
       LPAD(TO_CHAR(v.segments_perc, ''990.000''), 7) segments_perc,
       LPAD(TO_CHAR(v.extents_perc, ''990.000''), 7) extents_perc,
       LPAD(TO_CHAR(v.blocks_perc, ''990.000''), 7) blocks_perc,
       LPAD(TO_CHAR(v.bytes_perc, ''990.000''), 7) bytes_perc,
       LPAD(TO_CHAR(v.bytes_perc_cum, ''990.000''), 7) perc_cum
  FROM (
SELECT d.rank,
       d.segment_type,
       d.owner,
       d.segment_name,
       d.tablespace_name,
       d.segments,
       d.extents,
       d.blocks,
       d.bytes,
       d.segments_perc,
       d.extents_perc,
       d.blocks_perc,
       d.bytes_perc,
       d.bytes_perc_cum
  FROM top_200 d
 UNION ALL
SELECT TO_NUMBER(NULL) rank,
       NULL segment_type,
       NULL owner,
       NULL segment_name,
       ''TOP  20'' tablespace_name,
       st.segments,
       st.extents,
       st.blocks,
       st.bytes,
       st.segments_perc,
       st.extents_perc,
       st.blocks_perc,
       st.bytes_perc,
       TO_NUMBER(NULL) bytes_perc_cum
  FROM top_20_totals st
 UNION ALL
SELECT TO_NUMBER(NULL) rank,
       NULL segment_type,
       NULL owner,
       NULL segment_name,
       ''TOP 100'' tablespace_name,
       st.segments,
       st.extents,
       st.blocks,
       st.bytes,
       st.segments_perc,
       st.extents_perc,
       st.blocks_perc,
       st.bytes_perc,
       TO_NUMBER(NULL) bytes_perc_cum
  FROM top_100_totals st
 UNION ALL
SELECT TO_NUMBER(NULL) rank,
       NULL segment_type,
       NULL owner,
       NULL segment_name,
       ''TOP 200'' tablespace_name,
       st.segments,
       st.extents,
       st.blocks,
       st.bytes,
       st.segments_perc,
       st.extents_perc,
       st.blocks_perc,
       st.bytes_perc,
       TO_NUMBER(NULL) bytes_perc_cum
  FROM top_200_totals st
 UNION ALL
SELECT TO_NUMBER(NULL) rank,
       NULL segment_type,
       NULL owner,
       NULL segment_name,
       ''TOTAL'' tablespace_name,
       t.segments,
       t.extents,
       t.blocks,
       t.bytes,
       100 segemnts_perc,
       100 extents_perc,
       100 blocks_perc,
       100 bytes_perc,
       TO_NUMBER(NULL) bytes_perc_cum
  FROM totals t) v
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables and their indexes larger than 1 GB';
DEF main_table = 'DBA_SEGMENTS';
COL gb FOR 999990.000;
BEGIN
  :sql_text := '
WITH
tables AS (
SELECT /*+ &&sq_fact_hints. */
       owner,
       segment_name,
       SUM(bytes) bytes
  FROM dba_segments
WHERE segment_type LIKE ''TABLE%''
GROUP BY
       owner,
       segment_name
),
indexes AS (
SELECT /*+ &&sq_fact_hints. */
       owner,
       segment_name,
       SUM(bytes) bytes
  FROM dba_segments
WHERE segment_type LIKE ''INDEX%''
GROUP BY
       owner,
       segment_name
),
idx_tbl AS (
SELECT /*+ &&sq_fact_hints. */
       d.table_owner,
       d.table_name,
       SUM(i.bytes) bytes
  FROM indexes i,
       dba_indexes d
WHERE i.owner = d.owner
   AND i.segment_name = d.index_name
GROUP BY
       d.table_owner,
       d.table_name
),
total AS (
SELECT /*+ &&sq_fact_hints. */
       t.owner,
       t.segment_name table_name,
       (t.bytes + NVL(i.bytes, 0)) bytes
  FROM tables t,
       idx_tbl i
WHERE t.owner = i.table_owner(+)
   AND t.segment_name = i.table_name(+)
)
SELECT owner,
       table_name,
       ROUND(bytes / 1024 / 1024 / 1024, 3) gb
  FROM total
WHERE bytes > 1024 * 1024 * 1024
ORDER BY
       bytes DESC NULLS LAST
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Indexes larger than their Table';
DEF main_table = 'DBA_SEGMENTS';
COL gb FOR 999990.000;
BEGIN
  :sql_text := '
WITH
tables AS (
SELECT /*+ &&sq_fact_hints. */
       owner,
       segment_name,
       SUM(bytes) bytes
  FROM dba_segments
WHERE segment_type LIKE ''TABLE%''
GROUP BY
       owner,
       segment_name
),
indexes AS (
SELECT /*+ &&sq_fact_hints. */
       owner,
       segment_name,
       SUM(bytes) bytes
  FROM dba_segments
WHERE segment_type LIKE ''INDEX%''
GROUP BY
       owner,
       segment_name
),
idx_tbl AS (
SELECT /*+ &&sq_fact_hints. */
       d.table_owner,
       d.table_name,
       d.owner,
       d.index_name,
       SUM(i.bytes) bytes
  FROM indexes i,
       dba_indexes d
WHERE i.owner = d.owner
   AND i.segment_name = d.index_name
GROUP BY
       d.table_owner,
       d.table_name,
       d.owner,
       d.index_name
),
total AS (
SELECT /*+ &&sq_fact_hints. */
       t.owner table_owner,
       t.segment_name table_name,
       t.bytes t_bytes,
       i.owner index_owner,
       i.index_name,
       i.bytes i_bytes
  FROM tables t,
       idx_tbl i
WHERE t.owner = i.table_owner
   AND t.segment_name = i.table_name
   AND i.bytes > t.bytes
   AND t.bytes > 1024 * 1024 * 10 /* 10M */
)
SELECT table_owner,
       table_name,
       ROUND(t_bytes / 1024 / 1024 / 1024, 3) table_gb,
       index_owner,
       index_name,
       ROUND(i_bytes / 1024 / 1024 / 1024, 3) index_gb,
       ROUND((i_bytes - t_bytes) / 1024 / 1024 / 1024, 3) dif_gb,
       ROUND(100 * (i_bytes - t_bytes) / t_bytes, 1) dif_perc
  FROM total
ORDER BY
      table_owner,
       table_name,
       index_owner,
       index_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Candidate Tables for Partitioning';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
   owner, table_name, blocks, block_size, 
   round(blocks * block_size / 1048576) mb, 
   num_rows, avg_row_len, degree, sample_size, last_analyzed
from 
   dba_tables, 
   dba_tablespaces
where
   dba_tablespaces.tablespace_name = dba_tables.tablespace_name and
   (blocks * block_size / 1048576) >= 1024 and
   partitioned = ''NO'' and
   owner not in &&exclusion_list. and
   owner not in &&exclusion_list2.
order by owner, (blocks * block_size / 1048576) desc
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Segments in Reserved Tablespaces';
DEF main_table = 'DBA_SEGMENTS';
BEGIN
  :sql_text := '
-- provided by Simon Pane
SELECT /*+ &&top_level_hints. */ 
       s.owner, s.segment_type, s.tablespace_name, COUNT(1)
  FROM sys.dba_segments s
 WHERE s.owner NOT IN (''SYS'',''SYSTEM'',''OUTLN'',''AURORA$JIS$UTILITY$'',''OSE$HTTP$ADMIN'',''ORACACHE'',''ORDSYS'',
                       ''CTXSYS'',''DBSNMP'',''DMSYS'',''EXFSYS'',''MDSYS'',''OLAPSYS'',''SYSMAN'',''TSMSYS'',''WMSYS'',''XDB'')
   AND s.tablespace_name IN (''SYSTEM'',''SYSAUX'',''TEMP'',''TEMPORARY'',''RBS'',''ROLLBACK'',''ROLLBACKS'',''RBSEGS'')
   AND s.tablespace_name NOT IN (SELECT tablespace_name
                                   FROM sys.dba_tablespaces
                                  WHERE contents IN (''UNDO'',''TEMPORARY'')
                                )
and s.owner not in &&exclusion_list.
and s.owner not in &&exclusion_list2.
 GROUP BY s.owner, s.segment_type, s.tablespace_name
 ORDER BY 1,2,3';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Segment Shrink Recommendations';
DEF main_table = 'DBMS_SPACE';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
       *
FROM TABLE(dbms_space.asa_recommendations())
Where segment_owner not in &&exclusion_list. and
   segment_owner not in &&exclusion_list2.
order by reclaimable_space desc
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Objects in Recycle Bin';
DEF main_table = 'DBA_RECYCLEBIN';
BEGIN
  :sql_text := '
-- requested by Milton Quinteros
SELECT /*+ &&top_level_hints. */
       *
  FROM dba_recyclebin
 WHERE owner NOT IN &&exclusion_list.
   AND owner NOT IN &&exclusion_list2.
 ORDER BY
       owner,
       object_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Tables with excessive wasted space';
DEF main_table = 'DBA_TABLES';
BEGIN
  :sql_text := '
-- incarnation from health_check_4.4 (Jon Adams and Jack Agustin)
SELECT /*+ &&top_level_hints. */ 
   (round(blocks * block_size / 1048576)) - 
      (round(num_rows * avg_row_len * (1+(pct_free/100)) * decode (compression,''ENABLED'',0.50,1.00) / 1048576)) over_allocated_mb,
   owner, table_name, blocks, block_size, pct_free,
   round(blocks * block_size / 1048576) actual_mb,
   round(num_rows * avg_row_len * (1+(pct_free/100)) * decode (compression,''ENABLED'',0.50,1.00) / 1048576) estimate_mb,
   num_rows, avg_row_len, degree, compression, sample_size, to_char(last_analyzed,''MM/DD/RRRR'') last_analyzed
from
   dba_tables,
   dba_tablespaces
where
   dba_tablespaces.tablespace_name = dba_tables.tablespace_name and
   (blocks * block_size / 1048576) >= 10 and
   abs(round(blocks * block_size / 1048576) - round(num_rows * avg_row_len * (1+(pct_free/100)) * decode (compression,''ENABLED'',0.50,1.00) / 1048576)) / 
      (round(blocks * block_size / 1048576)) >= 0.25 and
   owner not in &&exclusion_list. and
   owner not in &&exclusion_list2.
order by 
   1 desc,
   owner, table_name
';
END;
/
@@edb360_9a_pre_one.sql

DEF title = 'Indexes with actual size greater than estimated';
DEF abstract = 'Actual and Estimated sizes for Indexes.';
DEF main_table = 'DBA_INDEXES';
VAR random1 VARCHAR2(30);
VAR random2 VARCHAR2(30);
EXEC :random1 := DBMS_RANDOM.string('A', 30);
EXEC :random2 := DBMS_RANDOM.string('X', 30);
COL random1 NEW_V random1 FOR A30;
COL random2 NEW_V random2 FOR A30;
SELECT :random1 random1, :random2 random2 FROM DUAL;
DELETE plan_table WHERE statement_id IN (:random1, :random2);
SET SERVEROUT ON;
-- log
SPO &&edb360_log..txt APP;
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
PRO &&title.
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
DECLARE
  sql_text CLOB;
BEGIN
  IF '&&db_version.' < '11.2.0.3' AND '&&db_version.' >= '11.2.0.4' THEN -- avoids DBMS_METADATA.GET_DDL: Query Against SYS.KU$_INDEX_VIEW Is Slow In 11.2.0.3 as per 1459841.1
    FOR i IN (SELECT idx.owner, idx.index_name
                FROM dba_indexes idx,
                     dba_tables tbl
               WHERE idx.owner NOT IN &&exclusion_list_single_quote. -- exclude non-application schemas
                 AND idx.owner NOT IN &&exclusion_list2_single_quote. -- exclude more non-application schemas
                 AND idx.index_type IN ('NORMAL', 'FUNCTION-BASED NORMAL', 'BITMAP', 'NORMAL/REV') -- exclude domain and lob
                 AND idx.status != 'UNUSABLE' -- only valid indexes
                 AND idx.temporary = 'N'
                 AND tbl.owner = idx.table_owner
                 AND tbl.table_name = idx.table_name
                 AND tbl.last_analyzed IS NOT NULL -- only tables with statistics
                 AND tbl.num_rows > 0 -- only tables with rows as per statistics
                 AND tbl.blocks > 128 -- skip small tables
                 AND tbl.temporary = 'N')
    LOOP
      BEGIN
        sql_text := 'EXPLAIN PLAN SET STATEMENT_ID = '''||:random1||''' FOR '||REPLACE(DBMS_METADATA.get_ddl('INDEX', i.index_name, i.owner), CHR(10), ' ');
        -- cbo estimates index size based on explain plan for create index ddl
        EXECUTE IMMEDIATE sql_text;
        -- index owner and name do not fit on statement_id, thus using object_owner and object_name, using statement_id as processing state
        DELETE plan_table WHERE statement_id = :random1 AND (other_xml IS NULL OR NVL(DBMS_LOB.instr(other_xml, 'index_size'), 0) = 0);
        UPDATE plan_table SET object_owner = i.owner, object_name = i.index_name, statement_id = :random2 WHERE statement_id = :random1;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE(i.owner||'.'||i.index_name||': '||SQLERRM);
          DBMS_OUTPUT.PUT_LINE(DBMS_LOB.substr(sql_text));
      END;
    END LOOP;
  ELSE
    DBMS_OUTPUT.PUT_LINE('*** skip on &&db_version. as per MOS 1459841.1');
  END IF;
END;
/
PRO
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO
SPO OFF;
SET SERVEROUT OFF;

BEGIN
  :sql_text := '
-- from estimate_index_size.sql
-- http://carlos-sierra.net/2014/07/18/free-script-to-very-quickly-and-cheaply-estimate-the-size-of-an-index-if-it-were-to-be-rebuilt/
WITH 
indexes AS (
SELECT /*+ &&sq_fact_hints. */
       pt.object_owner, 
       pt.object_name,
       TO_NUMBER(EXTRACTVALUE(VALUE(d), ''/info'')) estimated_bytes
  FROM plan_table pt,
       TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(pt.other_xml), ''/other_xml/info''))) d
 WHERE pt.statement_id = ''&&random2.''
   AND pt.other_xml IS NOT NULL -- redundant
   AND DBMS_LOB.instr(pt.other_xml, ''index_size'') > 0 -- redundant
   AND EXTRACTVALUE(VALUE(d), ''/info/@type'') = ''index_size'' -- grab index_size type
),
segments AS (
SELECT /*+ &&sq_fact_hints. */
       owner, segment_name, SUM(bytes) actual_bytes
  FROM dba_segments
 WHERE owner NOT IN &&exclusion_list. -- exclude non-application schemas
   AND owner NOT IN &&exclusion_list2. -- exclude more non-application schemas
   AND segment_type LIKE ''INDEX%''
HAVING SUM(bytes) > POWER(2, 20) -- only indexes with actual size > 1 MB
 GROUP BY
       owner,
       segment_name
),
list_bytes AS (
SELECT /*+ &&sq_fact_hints. */
       (s.actual_bytes - i.estimated_bytes) actual_minus_estimated,
       s.actual_bytes,
       i.estimated_bytes,
       i.object_owner,
       i.object_name
  FROM indexes i,
       segments s
 WHERE i.estimated_bytes > POWER(2, 20) -- only indexes with estimated size > 1 MB
   AND s.owner = i.object_owner
   AND s.segment_name = i.object_name
)
SELECT /*+ &&top_level_hints. */
       ROUND(actual_minus_estimated / POWER(2, 20)) actual_minus_estimated,
       ROUND(actual_bytes / POWER(2, 20)) actual_mb,
       ROUND(estimated_bytes / POWER(2, 20)) estimated_mb,
       object_owner owner,
       object_name index_name
  FROM list_bytes
 WHERE actual_minus_estimated > POWER(2, 20) -- only differences > 1 MB
 ORDER BY
       1 DESC,
       object_owner,
       object_name
';
END;
/
@@edb360_9a_pre_one.sql
DELETE plan_table WHERE statement_id IN (:random1, :random2);
