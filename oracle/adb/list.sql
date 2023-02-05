/*[[
    List files in Cloud Object Storage or Oracle directory. Usage: $$NAME {<directory>|{[<credential>] <URL>}} [<keyword>|-f"<filter>"] 
    <credential>: Optional if the default credential is defined via 'set credential'
    <URL>       : The Object Storage directory URL. can be '/<sub_files>' if the default URL is defined via 'set bucket'
    <directory> : Shoule be found in view all_directories
    <keyword>   : Can be:
                  1) the "LIKE" pattern that supports wildchars '%' and '_'
                  2) the 'REGEXP_LIKE' pattern
                  3) customized the WHERE clause by -f"<filter>"
    --[[
        @ARGS: 1
        @CHECK_ACCESS_CLOUD: DBMS_CLOUD={}
        &filter: {default={regexp_like(object_name,$KEYWORD$,'i')} f={}}
        &f     : default={0} f={1}
        &op    : default={list} delete={delete} copy={copy} move={move} unload={unload} view={view}
        &ops   : default={} delete={ deleted} copy={ copied} move={ to be moved} unload={ unloaded}
        &typ   : csv={"CSV","header":true} json={"JSON"} xml={"XML"} dmp={dmp}
        &gzip  : default={} gzip={,"compression":"gzip"}
    --]]
]]*/

var c refcursor "List of recent 100 matched objects&ops"
col bytes for tmb
set feed off
DECLARE
    C            SYS_REFCURSOR;
    op           VARCHAR2(10) := :op;
    keyword      VARCHAR2(32767) := COALESCE(:V4, :V3, :V2);
    dest         VARCHAR2(1000);
    target       VARCHAR2(1000) := CASE WHEN :V2=keyword THEN :V1 ELSE NVL(:V2,:V1) END;
    credential   VARCHAR2(1000) := CASE WHEN :V1=target THEN :credential ELSE :V1 END;
    stmt         VARCHAR2(2000);
    is_url1      BOOLEAN := FALSE;
    is_url2      BOOLEAN := FALSE;
    ctx          CLOB;
    content      BLOB;
    OID          INT;
    pos          INT;
    dest_offset  INTEGER := 1;
    src_offset   INTEGER := 1;
    lob_csid     NUMBER := dbms_lob.default_csid;
    lang_context INTEGER := dbms_lob.default_lang_ctx;
    warning      INTEGER;
    source_file  BFILE;
    t1           SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    tab          SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

    FUNCTION BLOB2CLOB(ctx IN OUT NOCOPY BLOB) RETURN CLOB IS
        v_clob CLOB;
    BEGIN
        dest_offset := 1;
        src_offset  := 1;
        dbms_lob.createtemporary(v_clob, TRUE);
        dbms_lob.ConvertToCLOB(v_clob,
                               ctx,
                               dbms_lob.getlength(ctx),
                               dest_offset,
                               src_offset,
                               lob_csid,
                               lang_context,
                               warning);
        dbms_lob.freetemporary(ctx);
        RETURN v_clob;
    END;

    PROCEDURE assert_credential IS
        cre VARCHAR2(1000);
    BEGIN
        SELECT MAX('"' || credential_name || '"')
        INTO   cre
        FROM   user_credentials
        WHERE  upper(credential_name) = upper(credential)
        AND    enabled = 'TRUE';
    
        IF cre IS NULL THEN
            raise_application_error(-20001, 'Credential "' || credential || '" is not enabled/found in user_credentials.');
        END IF;
        credential := cre;
    END;

    FUNCTION assert_dir(dir VARCHAR2,assert BOOLEAN:=TRUE) RETURN VARCHAR2 IS
        d VARCHAR2(1000);
    BEGIN
        SELECT MAX('"' || directory_name || '"') INTO d FROM all_directories WHERE upper(directory_name) = upper(dir);
    
        IF d IS NULL AND assert THEN
            raise_application_error(-20001, 'Directory "' || dir || '" is not found in all_directories.');
        END IF;
        RETURN d;
    END;

    FUNCTION assert_url(url VARCHAR2) RETURN VARCHAR2 IS
        d VARCHAR2(1000) := url;
    BEGIN
        IF instr(d, '/') = 1 THEN
            IF :objbucket IS NULL THEN
                raise_application_error(-20001, 'Please define the default bucket by "set bucket" when the URL is a relative path.');
            END IF;
            d := :objbucket || d;
        END IF;
        IF instr(nvl(d, 'x'), 'http') != 1 THEN
            raise_application_error(-20001, 'Invalid Object Storage URL: ' || d);
        END IF;
        RETURN d;
    END;
BEGIN
    IF op IN ('copy', 'move') THEN
        IF :V4 IS NOT NULL THEN
            dest       := :v3;
            target     := :v2;
            credential := :V1;
        ELSIF :V3 IS NOT NULL OR &f = 1 AND :V2 IS NOT NULL THEN
            dest       := :v2;
            target     := :v1;
            credential := :credential;
        ELSE
            raise_application_error(-20001, 'Arguments: [<credential>] <source> <destination> <keyword>');
        END IF;
    END IF;

    IF &f = 0 AND op != 'view' THEN
        keyword := REPLACE(REPLACE(keyword, '%', '.*'), '_', '.');
        IF op != 'list' AND keyword IS NULL THEN
            raise_application_error(-20001, 'Please specify the regexp_like string as the file filter.');
        ELSIF keyword IS NOT NULL THEN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT 1 FROM DUAL WHERE REGEXP_LIKE(:1,:2)'
                    USING 'XXX', keyword;
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error(-20001, 'Unexpected REGEXP_LIKE pattern: ' || keyword);
            END;
        ELSE
            keyword := '.';
        END IF;
    END IF;

    IF target LIKE '%/%' THEN
        is_url1 := TRUE;
        target  := assert_url(target);
        assert_credential;
    ELSE
        target  := assert_dir(target);
    END IF;

    IF op = 'unload' THEN
        IF :typ = 'dmp' THEN
            raise_application_error(-20001, 'Unsupported currently.');
        END IF;
    
        IF target LIKE '%/' THEN
            target := target || 'unload';
        END IF;
        dbms_cloud.export_data(credential_name => credential,
                               file_uri_list   => target,
                               query           => keyword,
                               format          => '{"type":&typ &gzip}',
                               operation_id    => OID);
        SELECT JSON_ARRAYAGG(JSON_OBJECT('OBJECT_NAME' VALUE FILE_URI_LIST,
                                         'CHECKSUM' VALUE STATUS,
                                         'Created' VALUE TO_CHAR(START_TIME, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                                         'LastModified' VALUE TO_CHAR(UPDATE_TIME, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')))
        INTO   CTX
        FROM   USER_LOAD_OPERATIONS
        WHERE  ID = OID;
    ELSIF op = 'view' THEN
        IF is_url1 THEN
            IF keyword IS NOT NULL THEN
                target := TRIM('/' FROM target) || '/' || keyword;
            ELSIF target LIKE '%/' THEN
                raise_application_error(-20001, 'Target must be a file: ' || target);
            END IF;
            content := dbms_cloud.get_object(credential_name => credential,
                                             object_uri      => target,
                                             startoffset     => 0,
                                             endoffset       => 1048576);
        ELSE
            target := TRIM('"' FROM target);
            IF keyword IS NULL THEN
                raise_application_error(-20001, 'Please specify the target file in directory ' || target);
            END IF;
            source_file := bfilename(target, keyword);
            BEGIN
                dbms_lob.fileopen(source_file);
            EXCEPTION
                WHEN OTHERS THEN
                    raise_application_error(-20001,
                                            SQLERRM || ' (Directory:"' || target || '"  File:"' || keyword || '")');
            END;
            dbms_lob.createtemporary(content, TRUE);
            dbms_lob.loadblobfromfile(content,
                                      source_file,
                                      least(1048576, dbms_lob.getlength(source_file)),
                                      dest_offset,
                                      src_offset);
            dbms_lob.fileclose(source_file);
        END IF;
        ctx         := blob2clob(content);
        dest_offset := 1;
        FOR i IN 1 .. 100 LOOP
            src_offset := dbms_lob.instr(ctx, chr(10), dest_offset);
            EXIT WHEN nvl(src_offset, 0) <= 0;
            tab.extend;
            tab(i) := TRIM(chr(13) FROM dbms_lob.substr(ctx, least(2000, src_offset - dest_offset), dest_offset));
            dest_offset := src_offset + 1;
        END LOOP;
        dbms_lob.freetemporary(ctx);
        OPEN c FOR
            SELECT ROWNUM "#", a.* FROM TABLE(tab) a;
    ELSE
        stmt := replace(replace(q'~
            SELECT JSON_ARRAYAGG(JSON_OBJECT(
                        OBJECT_NAME,
                        BYTES,
                        CHECKSUM,
                        'Created' VALUE TO_CHAR(CREATED, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                        'LastModified' VALUE TO_CHAR(LAST_MODIFIED, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')) RETURNING CLOB)
            FROM   (SELECT *
                    FROM   DBMS_CLOUD.LIST_$OBJ$ :target)
                    WHERE  &filter
                    ORDER  BY LAST_MODIFIED DESC FETCH FIRST decode(:op, 'list', 100, 1024) ROWS ONLY)~',
            '$OBJ$',CASE WHEN is_url1 THEN 'OBJECTS('''||credential||''',' ELSE 'FILES(' END),
            '$KEYWORD$','q''~'||keyword||'~''');
        EXECUTE IMMEDIATE stmt INTO ctx USING target,op;
        
        IF op NOT IN ('list') THEN
            SELECT * BULK COLLECT INTO T1 FROM JSON_TABLE(ctx, '$[*]' columns OBJECT_NAME VARCHAR2(1000));
        END IF;
    END IF;

    IF op IN ('copy', 'move') THEN
        IF dest LIKE '%/%' THEN
            is_url2 := TRUE;
            dest    := assert_url(dest);
            IF NOT is_url1 THEN
                assert_credential;
            END IF;
        ELSIF is_url1 THEN
            dest := assert_dir(dest);
        END IF;

        IF is_url1 OR is_url2 THEN
            stmt := replace(replace(replace(q'~
                DECLARE
                    t1 SYS.ODCIVARCHAR2LIST:=:t1;
                BEGIN
                    IF &f=0 AND t1.COUNT>1 THEN
                        dbms_cloud.bulk_$OP1$(:credential,:target,:dest,regex_filter=>:keyword,format=>JSON_OBJECT('priority' value 'HIGH'));
                    ELSE
                        FOR i IN 1..t1.COUNT LOOP
                            dbms_cloud.$OP2$_object(:credential,trim('/' from :target)||'/'||t1(i),trim('/' from :dest)$OP3$);
                            EXIT WHEN &f=0;
                        END LOOP;
                    END IF;
                END;~',
                '$OP1$',CASE is_url1 WHEN is_url2 THEN op WHEN true THEN 'download' ELSE 'upload' END),
                '$OP2$',CASE is_url1 WHEN is_url2 THEN op WHEN true THEN 'get'      ELSE 'put'    END),
                '$OP3$',CASE WHEN is_url1!=is_url2 THEN ',file_name=>t1(i)' 
                             WHEN is_url1=is_url2 AND regexp_like(dest,'\.\w+$') THEN '' 
                             ELSE q'[||'/'||t1(i)]' 
                        END);
            EXECUTE IMMEDIATE stmt USING 
                t1,credential,
                CASE WHEN is_url1 THEN target ELSE dest   END,
                CASE WHEN is_url1 THEN dest   ELSE target END,
                keyword;
        ELSE--copy file in directory
            IF assert_dir(dest,false) IS NOT NULL THEN
                dest    := trim('"' from assert_dir(dest,false));
                is_url2 := TRUE;
            END IF;
            target := trim('"' from target);
            FOR i IN 1..t1.COUNT LOOP
                IF is_url2 THEN
                    utl_file.fcopy(target,t1(i),dest,t1(i));
                ELSE
                    utl_file.fcopy(target,t1(i),target,dest);
                    EXIT WHEN i=1;
                END IF;
            END LOOP;
        END IF;
    END IF;

    IF op IN ('delete', 'move') THEN
        IF is_url1 THEN
            IF NOT is_url2 THEN
                IF &f = 0 AND t1.COUNT > 1 THEN
                    DBMS_CLOUD.BULK_DELETE(credential, target, keyword);
                ELSE
                    FOR i IN 1 .. t1.COUNT LOOP
                        DBMS_CLOUD.DELETE_OBJECT(credential, TRIM('/' FROM target) || '/' || t1(i));
                    END LOOP;
                END IF;
            END IF;
        ELSE
            FOR i IN 1 .. t1.COUNT LOOP
                DBMS_CLOUD.DELETE_FILE(target, t1(i));
            END LOOP;
        END IF;
    END IF;

    IF c IS NULL THEN
        OPEN c FOR
            SELECT *
            FROM   JSON_TABLE(ctx, '$[*]' COLUMNS 
                              OBJECT_NAME VARCHAR2(256),
                              BYTES INT,
                              CHECKSUM VARCHAR2(64),
                              Created VARCHAR2(40),
                              LastModified VARCHAR2(40))
            WHERE  ROWNUM <= 100;
    END IF;
    :c := c;
END;
/
