/*[[List files under the specific directory. Usage: @@NAME <directory> [<keyword>] [<tailing_rows>] [-lrt]
    -lrt: order by last modified instead of file name
    --[[
        &ord: default={order by lower(fname_krbmsft)} lrt={}
    --]]
]]*/
SET FEED OFF
DECLARE
    pattern VARCHAR2(512)  :=trim('/' from :V1);
    keyword VARCHAR2(512)  :='%'||trim('%' from lower(:V2))||'%';
    rn      PLS_INTEGER    := regexp_substr(:V3,'^\d+$');
    ns      VARCHAR2(512);
    indx    PLS_INTEGER:=0;
BEGIN
    dbms_output.enable(null);
    IF pattern IS NULL THEN
        SELECT trim(trim('/' from max(value)))
        INTO   pattern
        FROM   v$parameter
        WHERE  name='db_recovery_file_dest';
    END IF;
    IF pattern NOT LIKE '+%' THEN
        pattern := '/'|| pattern;
    END IF;
    pattern := pattern || '/';

    sys.dbms_backup_restore.searchfiles(
        pattern => pattern ,
        ns      => ns,
        omf     => CASE WHEN pattern LIKE '+%' THEN true ELSE false END);
    FOR r IN(SELECT *
             FROM   (SELECT *
                     FROM   (SELECT rownum r, fname_krbmsft
                             FROM   (SELECT * FROM sys.x$krbmsft a WHERE lower(fname_krbmsft) LIKE keyword &ord))
                     ORDER  BY r DESC)
             WHERE  rn IS NULL
             OR     ROWNUM <= rn
             ORDER  BY R) LOOP
        indx := indx + 1;
        dbms_output.put_line(lpad(indx,5)||':  '||r.fname_krbmsft);
    END LOOP;
END;
/