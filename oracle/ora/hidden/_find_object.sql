
set printvar off feed off
var object_owner   VARCHAR2;
VAR object_type    VARCHAR2;
VAR object_name    VARCHAR2;
VAR object_subname VARCHAR2;
VAR object_id      NUMBER;
    
DECLARE /*INTERNAL_DBCLI_CMD*/
    schem         VARCHAR2(100);
    part1         VARCHAR2(100);
    part2         VARCHAR2(100);
    part2_temp    VARCHAR2(100);
    dblink        VARCHAR2(100);
    part1_type    PLS_INTEGER;
    object_number PLS_INTEGER;
    flag          BOOLEAN := TRUE;
    obj_type      VARCHAR2(100);
    objs          VARCHAR2(2000) := 'dba_objects';
    target        VARCHAR2(100) := :V1;
BEGIN
    <<CHECKER>>
    FOR i IN 0 .. 9 LOOP
        BEGIN
            sys.dbms_utility.name_resolve(NAME          => target,
                                          CONTEXT       => i,
                                          SCHEMA        => schem,
                                          part1         => part1,
                                          part2         => part2,
                                          dblink        => dblink,
                                          part1_type    => part1_type,
                                          object_number => object_number);
            IF part2 IS NOT NULL AND part1 IS NULL THEN
                part1:=part2;
                part2:=null;
            END IF;
            EXIT;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END LOOP;

    IF schem IS NULL AND flag AND USER != sys_context('USERENV', 'CURRENT_SCHEMA') AND instr(target,'.')=0 THEN
        flag   := FALSE;
        target := sys_context('USERENV', 'CURRENT_SCHEMA') || '.' || target;
        GOTO CHECKER;
    END IF;

    BEGIN
        EXECUTE IMMEDIATE 'select 1 from dba_objects where rownum<1';
    EXCEPTION
        WHEN OTHERS THEN
            objs := 'all_objects';
    END;

    target := REPLACE(upper(target),' ');

    IF schem IS NULL AND objs != 'all_objects' THEN
        flag  := FALSE;
        schem := regexp_substr(target, '[^\.]+', 1, 1);
        part1 := regexp_substr(target, '[^\.]+', 1, 2);
        objs  := 'dba_objects a WHERE owner IN(''PUBLIC'',sys_context(''USERENV'', ''CURRENT_SCHEMA''),''' ||schem || ''') AND object_name IN(''' || schem || ''',''' || part1 || '''))';
    ELSE
        flag  := TRUE;
        objs  := objs || ' a WHERE OWNER in(''PUBLIC'',''' || schem || ''') AND OBJECT_NAME=''' || part1 || ''')';
    END IF;

    objs:='SELECT /*+no_expand*/ 
           MIN(OBJECT_TYPE)    keep(dense_rank first order by s_flag),
           MIN(OWNER)          keep(dense_rank first order by s_flag),
           MIN(OBJECT_NAME)    keep(dense_rank first order by s_flag),
           MIN(SUBOBJECT_NAME) keep(dense_rank first order by s_flag),
           MIN(OBJECT_ID)      keep(dense_rank first order by s_flag)
    FROM (
        SELECT a.*,
               case when owner=''' || schem || ''' then 0 else 100 end +
               case when ''' || target || q'[' like upper('%'||OBJECT_NAME||nullif('.'||SUBOBJECT_NAME||'%','.%')) then 0 else 10 end +
               case substr(object_type,1,3) when 'TAB' then 1 when 'CLU' then 2 else 3 end s_flag
        FROM   ]' || objs;       

    --dbms_output.put_line(objs);
    EXECUTE IMMEDIATE objs
        INTO obj_type, schem, part1, part2_temp,object_number;

    IF part2 IS NULL THEN
        IF part2_temp IS NULL AND NOT flag THEN
            part2_temp := regexp_substr(target, '[^\.]+', 1, CASE WHEN part1=regexp_substr(target, '[^\.]+', 1, 1) THEN 2 ELSE 3 END);
        END IF;
        part2 := part2_temp;
    END IF;
    
    IF object_number IS NULL AND target IS NOT NULL AND :V2 IS NULL THEN
        raise_application_error(-20001,'Cannot find target object "&V1"!');
    END IF;

    :object_owner   := schem;
    :object_type    := obj_type;
    :object_name    := part1;
    :object_subname := part2;
    :object_id      := object_number;
END;
/
set printvar back feed back