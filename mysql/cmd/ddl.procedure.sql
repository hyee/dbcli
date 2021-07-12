COL "Create Procedure" new_value ddl
COL "Procedure,Function" NOPRINT
SHOW CREATE PROCEDURE `&object_owner`.`&object_name`
save ddl &object_owner..&object_name..sql