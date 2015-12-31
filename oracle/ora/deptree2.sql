/*[[Shows the accessible dependencies on the given object. Usage: @@NAME [owner.]object_name]]*/

ora _find_object &V1
set feed off
var cur REFCURSOR;

DECLARE
    c   INT;
    o   DBMSOUTPUT_LINESARRAY;
BEGIN
    dbms_output.disable;
    dbms_output.enable(NULL);
    dbms_utility.get_dependency(:object_type, :object_owner, :object_name);
    dbms_output.get_lines(o, c);
    EXECUTE IMMEDIATE 'alter session set nls_date_format=''YYYY-MM-DD HH24:MI:SS''';

    OPEN :cur FOR
        SELECT /*+no_merge(o)*/
                 r "#",
                 object_name,
                 object_type,
                 0+regexp_substr(info, '[^/]+', 1, 1) OBJECT_ID,
                 nullif(0+regexp_substr(info, '[^/]+', 1, 2),0) DATA_OBJECT_ID,
                 regexp_substr(info, '[^/]+', 1, 6) STATUS,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 3)) CREATED,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 4)) LAST_DDL_TIME,
                 TO_DATE(regexp_substr(info, '[^/]+', 1, 5)) TIMESTAMP,
                 regexp_substr(info, '[^/]+', 1, 7) TEMPORARY
        FROM   (SELECT r,object_name,regexp_substr(obj, '[^\.]+', 1, 3) object_type,
                        (SELECT OBJECT_ID || '/' || nvl(DATA_OBJECT_ID,0) || '/' || CREATED || '/' ||
                                LAST_DDL_TIME || '/' || TIMESTAMP || '/' || STATUS || '/' || TEMPORARY
                          FROM   all_objects
                          WHERE  owner = regexp_substr(obj, '[^\.]+', 1, 1)
                          AND    object_name = regexp_substr(obj, '[^\.]+', 1, 2)
                          AND    object_type = regexp_substr(obj, '[^\.]+', 1, 3)) info
                 FROM   (SELECT rownum r,
                                regexp_replace(COLUMN_VALUE, '([\* ]+)(.*) ([^ \(]+).*','\1\3') object_name,
                                regexp_replace(COLUMN_VALUE, '([\* ]+)(.*) ([^ \(]+).*', '\3.\2') obj
                         FROM   TABLE(o)
                         WHERE  COLUMN_VALUE LIKE '*%')) o
        ORDER BY r;
END;
/