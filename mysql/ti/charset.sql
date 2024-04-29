/*[[Show db character sets & collations. Usage: @@NAME [<keyword>]
]]*/
ECHO CHARACTER_SETS:
ECHO ===============
SELECT * FROM information_schema.CHARACTER_SETS where lower(DEFAULT_COLLATE_NAME) like lower('%&v1%');

ECHO COLLATIONS:
ECHO ===========
SELECT * FROM information_schema.collations where lower(COLLATION_NAME) like lower('%&v1%') limit 100;