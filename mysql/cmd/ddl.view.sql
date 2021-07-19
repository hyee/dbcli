ENV COLWRAP 120
COL "Create View" new_value ddl
COL "VIEW,TABLE" NOPRINT
SHOW CREATE VIEW `&object_owner`.`&object_name`

save ddl &object_owner..&object_name..sql