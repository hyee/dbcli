COL "Create Function" new_value ddl
COL "Procedure,Function" NOPRINT
SHOW CREATE FUNCTION `&object_owner`.`&object_name`
save ddl &object_owner..&object_name..sql