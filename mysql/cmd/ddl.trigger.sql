COL "Sql Original Statement" new_value ddl
COL "Trigger" NOPRINT
SHOW CREATE TRIGGER `&object_owner`.`&object_name`
save ddl &object_owner..&object_name..sql