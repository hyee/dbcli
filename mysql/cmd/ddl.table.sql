COL "Create Table" new_value ddl
SHOW CREATE TABLE `&object_owner`.`&object_name`;
SELECT CONCAT('ALTER TABLE `',
              TABLE_NAME,
              '` ',
              'MODIFY COLUMN `',
              COLUMN_NAME,
              '` ',
              IF(UPPER(DATA_TYPE) = 'INT',
                 REPLACE(SUBSTRING_INDEX(UPPER(COLUMN_TYPE), ')', 1), 'INT', 'INTEGER'),
                 UPPER(COLUMN_TYPE)),
              ') UNSIGNED NOT NULL AUTO_INCREMENT;') `AUTO_INCREMENT`
FROM   information_schema.columns
WHERE  table_schema = :object_owner
AND    table_name   = :object_name
AND    UPPER(extra) = 'AUTO_INCREMENT'
;SELECT  INDEX_NAME,
        CONCAT('ALTER TABLE ',
              TABLE_NAME,
              ' ',
              'ADD ',
              IF(NON_UNIQUE = 1,
                 CASE UPPER(INDEX_TYPE)
                     WHEN 'FULLTEXT' THEN
                      'FULLTEXT INDEX'
                     WHEN 'SPATIAL' THEN
                      'SPATIAL INDEX'
                     ELSE
                      CONCAT('INDEX ', INDEX_NAME, ' USING ', INDEX_TYPE)
                 END,
                 IF(UPPER(INDEX_NAME) = 'PRIMARY',
                    CONCAT('PRIMARY KEY USING ', INDEX_TYPE),
                    CONCAT('UNIQUE INDEX ', INDEX_NAME, ' USING ', INDEX_TYPE))),
              '(',
              GROUP_CONCAT(DISTINCT CONCAT('', COLUMN_NAME, '') ORDER BY SEQ_IN_INDEX ASC SEPARATOR ', '),
              ');') AS 'Create Index'
FROM   information_schema.statistics
WHERE  table_schema = :object_owner
AND    table_name   = :object_name
AND    index_name  != 'PRIMARY'
GROUP  BY TABLE_NAME, INDEX_NAME, NON_UNIQUE, INDEX_TYPE
ORDER  BY INDEX_NAME;

save ddl &object_owner..&object_name..sql