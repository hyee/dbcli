
set verify off feed off
var object_owner   VARCHAR2;
VAR object_type    VARCHAR2;
VAR object_name    VARCHAR2;
VAR object_subname VARCHAR2;
VAR object_id      NUMBER;

DECLARE /*INTERNAL_DBCLI_CMD*/
    schem         VARCHAR2(128);
    part1         VARCHAR2(128);
    part2         VARCHAR2(128);
    part2_temp    VARCHAR2(128);
    dblink        VARCHAR2(128);
    part1_type    PLS_INTEGER;
    object_number PLS_INTEGER;
    cnt           PLS_INTEGER;
    flag          BOOLEAN := TRUE;
    obj_type      VARCHAR2(128);
    objs          VARCHAR2(2000) := 'dba_objects';
    stmt          VARCHAR2(4000);
    target        VARCHAR2(500) := trim(:V1);
    isUpper       BOOLEAN := true;
BEGIN

    BEGIN
        EXECUTE IMMEDIATE 'select 1 from dba_objects where rownum<1';
    EXCEPTION WHEN OTHERS THEN
        objs := 'all_objects';
    END;
    
    <<CHECKER>>
    IF NOT regexp_like(target,'^\d+$') THEN
        IF regexp_like(target,'^[^"].*" *\. *".+[^"]$') OR NOT isUpper THEN
            target := '"'||target||'"';
        END IF;
        

        BEGIN 
            sys.dbms_utility.name_tokenize(target,schem,part1,part2,dblink,part1_type);
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE=-931 THEN --ORA-00931: Missing identifier
                sys.dbms_utility.name_tokenize('"'||REPLACE(UPPER(target),'.','"."')||'"',schem,part1,part2,dblink,part1_type);
            END IF;
        END;
        target:='"'||REPLACE(trim('.' from schem||'.'||part1||'.'||part2),'.','"."')||'"';
        
        schem:=null;
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
                EXIT WHEN schem IS NOT NULL;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END LOOP;

        IF schem IS NULL AND flag AND USER != sys_context('USERENV', 'CURRENT_SCHEMA') AND instr(target,'.')=0 THEN
            flag   := FALSE;
            target := sys_context('USERENV', 'CURRENT_SCHEMA') || '.' || target;
            GOTO CHECKER;
        END IF;
    ELSE
        EXECUTE IMMEDIATE 'select max(to_char(owner)),max(to_char(object_name)),max(to_char(subobject_name)),max(object_id) from '||objs||' where object_id=:1' 
        INTO schem,part1,part2,object_number
        USING 0+target;
    END IF;
   
    IF schem IS NULL THEN
        flag  := FALSE;
        schem := regexp_substr(target, '[^\."]+', 1, 1);
        part1 := regexp_substr(target, '[^\."]+', 1, 2);
        IF part1 IS NULL THEN
            part1 := trim('"' from target);
            schem := null;
            stmt  := objs||' a WHERE nvl(:1,''X'')=''X'' AND object_name =:3)';
        ELSE
            part2_temp := schem;
            BEGIN
                EXECUTE IMMEDIATE 'SELECT MAX(username) FROM DBA_USERS WHERE upper(username)=:1' INTO schem using upper(schem);
            EXCEPTION WHEN OTHERS THEN 
                SELECT MAX(username) INTO schem FROM ALL_USERS WHERE upper(username)=upper(schem);
            END;

            IF schem IS NOT NULL THEN
                stmt  := objs||' a WHERE owner=:1 AND object_name =:2)';
            ELSE
                part1      := nvl(part2_temp,trim('"' from target));
                stmt       := objs||' a WHERE nvl(:1,''Y'')=''Y'' AND object_name=:3)';
            END IF;            
        END IF;
    ELSE
        flag  := TRUE;
        stmt  := objs|| ' a WHERE OWNER IN(''SYS'',''PUBLIC'',:1) AND OBJECT_NAME=:3)';
    END IF;

    stmt:=q'[SELECT /*+no_expand*/
           MIN(to_char(OBJECT_TYPE))    keep(dense_rank first order by s_flag,object_id),
           MIN(to_char(OWNER))          keep(dense_rank first order by s_flag,object_id),
           MIN(to_char(OBJECT_NAME))    keep(dense_rank first order by s_flag,object_id),
           MIN(to_char(SUBOBJECT_NAME)) keep(dense_rank first order by s_flag,object_id),
           MIN(to_number(OBJECT_ID))    keep(dense_rank first order by s_flag)
    FROM (
        SELECT /*+INDEX_SS(a) MERGE(A) no_expand*/ a.*,
               case when owner=:1 then 0 else 100 end +
               case when :2 like '%"'||OBJECT_NAME||'"'||nvl2(SUBOBJECT_NAME,'."'||SUBOBJECT_NAME||'"%','') then 0 else 10 end +
               case substr(object_type,1,3) when 'TAB' then 1 when 'CLU' then 2 else 3 end s_flag
        FROM   ]' || stmt;

    /*stmt:=replace(replace(replace(stmt,':1',''''||schem||''''),':2',''''||target||''''),':3',''''||part1||'''');
    dbms_output.put_line(stmt);*/

    EXECUTE IMMEDIATE stmt
        INTO obj_type, schem, part1, part2_temp,object_number USING schem,target,schem, part1;
    
    IF part2 IS NULL THEN
        IF part2_temp IS NULL AND NOT flag THEN
            part2_temp := regexp_substr(target, '[^\."]+', 1, CASE WHEN part1=regexp_substr(target, '[^\."]+', 1, 1) THEN 2 ELSE 3 END);
        END IF;
        part2 := part2_temp;
    END IF;

    IF part1 IS NULL AND target IS NOT NULL THEN
        IF isUpper AND target=upper(target) AND :V1!=UPPER(:V1) THEN
            target  := trim(:V1);
            isUpper := false;
            GOTO CHECKER;
        ELSIF :V2 IS NULL THEN
            raise_application_error(-20001,'Cannot find target object '||target||'!');
        END IF;
    END IF;
    
    :object_owner   := schem;
    :object_type    := obj_type;
    :object_name    := part1;
    :object_subname := part2;
    :object_id      := object_number;
END;
/
set verify back feed back