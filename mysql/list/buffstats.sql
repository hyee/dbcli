/*[[Show schema-based InnoDB buffer stats]]*/
COL data_size format KMG
COL allocated format KMG
SELECT IF(LOCATE('.', ibp.table_name) = 0, 'InnoDB System', 
          REPLACE(SUBSTRING_INDEX(ibp.table_name, '.', 1), '`', '')) AS object_schema,
       SUM(IF(ibp.compressed_size = 0, 16384, compressed_size)) AS allocated,
       SUM(ibp.data_size) AS data_size,
       COUNT(ibp.page_number) AS pages,
       COUNT(IF(ibp.is_hashed = 'YES', 1, 0)) AS pages_hashed,
       COUNT(IF(ibp.is_old = 'YES', 1, 0)) AS pages_old,
       ROUND(SUM(ibp.number_records)/COUNT(DISTINCT ibp.index_name)) AS rows_cached 
  FROM information_schema.innodb_buffer_page ibp 
 WHERE table_name IS NOT NULL
 GROUP BY object_schema
 ORDER BY SUM(IF(ibp.compressed_size = 0, 16384, compressed_size)) DESC 