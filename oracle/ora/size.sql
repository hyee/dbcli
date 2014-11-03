/*[[
Show object size. Usage: ora size object_name [owner]
]]*/
WITH r AS
 (SELECT DISTINCT owner, segment_name
  FROM   Dba_Segments
  WHERE  upper(owner || '.' || segment_name) LIKE upper('%' || :V2 || '.' || :V1)),
R2 AS
 (SELECT owner, index_name segment_name,table_owner,table_name
  FROM   Dba_Indexes
  WHERE  (table_owner, table_name) IN (SELECT * FROM r)
  UNION
  SELECT owner, segment_name,owner, table_name
  FROM   Dba_lobs
  WHERE  (owner, table_name) IN (SELECT * FROM r)
  UNION
  SELECT r.*,r.*
  FROM   r)
SELECT owner,
       NVL(segment_name,'--TOTAL--') segment_name,
       MAX(segment_type) segment_type,
       round(SUM(bytes / 1024 / 1024), 3) MB,
       trunc(AVG(INITIAL_EXTENT)) INIEXT,
       MAX(max_extents) MAXEXT
FROM   Dba_Segments join r2
using (owner, segment_name)
GROUP  BY grouping sets((owner, segment_name,table_owner,table_name),(table_owner,table_name))
