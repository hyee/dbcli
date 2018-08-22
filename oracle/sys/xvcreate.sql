/*[[Used to create xv$ views based on SYS x$ tables, so that normal user can run the scripts under command 'sys'.]]*/
set feed off
BEGIN
    dbms_output.put_line('$HIY$Run following statement with SYSDBA:'||chr(10)||rpad('=',36,'=')||'$NOR$');
    dbms_output.put_line(replace(q'[
        DECLARE
            target_user VARCHAR2(128) := 'SELECT_CATALOG_ROLE'; --Change target grantee here
        BEGIN
            dbms_output.enable(NULL);
            FOR r IN (SELECT * FROM v$fixed_table WHERE NAME LIKE 'X$%' AND TYPE = 'TABLE') LOOP
                BEGIN
                    EXECUTE IMMEDIATE 'create or replace view SYS.XV' || substr(r.name,2,28) || ' AS SELECT * FROM SYS.' || r.name;
                    EXECUTE IMMEDIATE 'grant select on SYS.XV' || substr(r.name,2,28) || ' TO ' || target_user;
                EXCEPTION
                    WHEN OTHERS THEN
                        dbms_output.put_line('Error when creating refs to SYS.'||r.name||': '||SQLERRM);
                END;
            END LOOP;
        END;
        /]',chr(10)||'        ',chr(10)));
END;
/