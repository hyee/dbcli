/*[[Get DDL statement. Usage: ddl [owner.]<object_name>]]*/


SET FEED OFF PRINTVAR OFF
VAR TEXT CLOB;

DECLARE
    v_default     NUMBER := DBMS_METADATA.SESSION_TRANSFORM;
    SCHEM         VARCHAR2(30);
    part1         VARCHAR2(30);
    part2         VARCHAR2(30);
    part2_temp    VARCHAR2(30);
    dblink        VARCHAR2(30);
    part1_type    PLS_INTEGER;
    object_number PLS_INTEGER;
    obj_type      VARCHAR2(30);
    TYPE t IS TABLE OF VARCHAR2(30);
    t1 t := t('TABLE',
              'PL/SQL',
              'SEQUENCE',
              'TRIGGER',
              'JAVA_SOURCE',
              'JAVA_RESOURCE',
              'JAVA_CLASS',
              'TYPE',
              'JAVA_SHARED_DATA',
              'INDEX');
BEGIN
    FOR i IN 0 .. 9 LOOP
        BEGIN
            sys.dbms_utility.name_resolve(NAME          => :V1,
                                          CONTEXT       => i,
                                          SCHEMA        => SCHEM,
                                          part1         => part1,
                                          part2         => part2,
                                          dblink        => dblink,
                                          part1_type    => part1_type,
                                          object_number => object_number);
            SELECT /*+no_expand*/
             MIN(OBJECT_TYPE), MIN(OWNER), MIN(OBJECT_NAME), MIN(SUBOBJECT_NAME)
            INTO   obj_type, SCHEM, part1, part2_temp
            FROM   ALL_OBJECTS
            WHERE  object_id = object_number;
            IF part2 IS NULL THEN
                part2 := part2_temp;
            END IF;
            EXIT;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END LOOP;
    if obj_type is null then
        :text := 'Cannot identify the target object!';
    else
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SQLTERMINATOR', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SEGMENT_ATTRIBUTES', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'STORAGE', FALSE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'TABLESPACE', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'SPECIFICATION', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'BODY', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS', TRUE);
        DBMS_METADATA.SET_TRANSFORM_PARAM(v_default, 'CONSTRAINTS_AS_ALTER', TRUE);
        :text := dbms_metadata.get_ddl(REPLACE(obj_type, ' ', '_'), part1, SCHEM);
    end if;
END;
/

print text