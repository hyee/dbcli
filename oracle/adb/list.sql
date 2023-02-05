/*[[
    List files in Cloud Object Storage or Oracle directory. Usage: @@NAME {<directory>|{[<credential>] <URL>}} [<keyword>|-f"<filter>"] 
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
        &filter: {default={regexp_like(object_name,keyword,'i')} 
                  f={}
                 }
        &f     : default={0} f={1}
        &op    : default={list} delete={delete} copy={copy} move={move} unload={unload} view={view}
        &ops   : default={} delete={deleted} copy={copied} move={to be moved} unload={unloaded}
        &typ   : csv={"CSV","header":true} json={"JSON"} xml={"XML"} dmp={dmp}
        &gzip  : default={} gzip={,"compression":"gzip"}
    --]]
]]*/

var c refcursor "List of recent 100 matched objects&ops"
col bytes for tmb
set feed off
DECLARE
    C          SYS_REFCURSOR;
    op         VARCHAR2(10)   := :op;
    keyword    VARCHAR2(32767):= COALESCE(:V4,:V3,:V2);
    dest       VARCHAR2(1000);
    target     VARCHAR2(1000) := CASE WHEN :V2=keyword THEN :V1 ELSE NVL(:V2,:V1) END;
    credential VARCHAR2(1000) := CASE WHEN :V1=target THEN :credential ELSE :V1 END;
    is_url     BOOLEAN := FALSE;
    ctx        CLOB;
    content    BLOB;
    type       t IS TABLE OF VARCHAR2(1000);
    t1         t;
    oid        INT;
    pos        INT;

    dest_offset  INTEGER := 1;
    src_offset   INTEGER := 1;
    lob_csid     NUMBER  := dbms_lob.default_csid;
    lang_context INTEGER := dbms_lob.default_lang_ctx;
    warning      INTEGER;
    source_file  BFILE;
    tab          SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

    FUNCTION BLOB2CLOB(ctx IN OUT NOCOPY BLOB) RETURN CLOB IS
        v_clob       CLOB;
    BEGIN
        dest_offset := 1;
        src_offset  := 1;
        dbms_lob.createtemporary(v_clob, TRUE);
        dbms_lob.ConvertToCLOB(v_clob, ctx, dbms_lob.getlength(ctx), dest_offset, src_offset, lob_csid, lang_context, warning);
        dbms_lob.freetemporary(ctx);
        RETURN v_clob;
    END;

    PROCEDURE asser_credential IS
        cre VARCHAR2(1000);
    BEGIN
        SELECT MAX('"'||credential_name||'"')
        INTO   cre
        FROM   user_credentials
        WHERE  upper(credential_name)=upper(credential)
        AND    enabled='TRUE';

        IF cre IS NULL THEN
            raise_application_error(-20001,'Credential "'||credential||'" is not enabled/found in user_credentials.');
        END IF;
        credential := cre;
    END;

    FUNCTION assert_dir(dir VARCHAR2) RETURN VARCHAR2 IS
        d VARCHAR2(1000);
    BEGIN
        SELECT MAX('"'||directory_name||'"')
        INTO   d
        FROM   all_directories
        WHERE  upper(directory_name)=upper(dir);

        IF d IS NULL THEN
            raise_application_error(-20001,'Credential "'||dir||'" is not found in all_directories.');
        END IF;
        return d;
    END;

    FUNCTION assert_url(url VARCHAR2) RETURN VARCHAR2 is
        d VARCHAR2(1000):=url;
    BEGIN
        IF instr(d,'/')=1 then
            IF :objbucket IS NULL THEN
                raise_application_error(-20001,'Please define the default bucket by "set bucket" when the URL is a relative path.');
            END IF;
            d:=:objbucket||d;
        END IF;
        IF instr(nvl(d,'x'),'http')=0 THEN
            raise_application_error(-20001,'Invalid Object Storage URL: '||d);
        END IF;
        RETURN d;
    END;
BEGIN
    IF op in('copy','move') THEN
        IF :V4 IS NOT NULL THEN
            dest   := :v3;
            target := :v2;
            credential := :V1;
        ELSIF :V3 IS NOT NULL THEN
            dest   := :v2;
            target := :v1;
            credential := :credential;
        ELSE
            raise_application_error(-20001,'Arguments: [<credential>] <source> <destination> {<keyword>|<REGEXP_LIKE pattern>}');
        END IF;

        IF target NOT like '%/%' AND dest NOT like '%/%' THEN
            raise_application_error(-20001,'one of source/destination must be an Object Storage URL.');
        ELSIF target like '%/%' AND dest like '%/%' THEN
            raise_application_error(-20001,'one of source/destination must be an Oracle directory.');
        END if;
    END IF;

    IF &f=0 AND op!='view' THEN
        keyword := replace(replace(keyword,'%','.*'),'_','.');
        IF op!='list' AND keyword IS NULL THEN
            raise_application_error(-20001,'Please specify the regexp_like string as the file filter.');
        ELSIF keyword IS NOT NULL THEN
            BEGIN
                EXECUTE IMMEDIATE 'SELECT 1 FROM DUAL WHERE REGEXP_LIKE(:1,:2)'
                USING 'XXX',keyword;
            EXCEPTION WHEN OTHERS THEN 
                raise_application_error(-20001,'Unexpected REGEXP_LIKE pattern: '||keyword);
            END;
        ELSE
            keyword := '.';
        END IF;
    END IF;
    
    IF target like '%/%' THEN
        is_url := TRUE;
    END IF;

    IF op = 'unload' THEN
        IF :typ='dmp' THEN
            raise_application_error(-20001,'Unsupported currently.');
        END IF;
        target := assert_url(target);
        asser_credential;
        IF target like '%/' THEN
            target := target||'unload';
        END IF;
        dbms_cloud.export_data(
            credential_name => credential,
            file_uri_list   => target,
            query           => keyword,
            format          => '{"type":&typ &gzip}',
            operation_id    => oid);
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
                              'OBJECT_NAME' value FILE_URI_LIST,
                              'CHECKSUM' value STATUS,
                              'Created' VALUE TO_CHAR(START_TIME,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                              'LastModified' VALUE TO_CHAR(UPDATE_TIME,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')))
        INTO  CTX
        FROM  USER_LOAD_OPERATIONS
        WHERE ID=oid;
    ELSIF op = 'view' then
        IF is_url THEN
            target := assert_url(target);
            asser_credential;
            IF keyword IS NOT NULL THEN
                target := trim('/' from target)||'/'||keyword;
            ELSIF target like '%/' THEN
                raise_application_error(-20001,'Target must be a file: '||target);
            END IF;
            content := dbms_cloud.get_object(
                            credential_name => credential,
                            object_uri  => target,
                            startoffset=> 0,
                            endoffset  => 1048576);
        ELSE
            target := trim('"' from assert_dir(target));
            IF keyword IS NULL THEN
                raise_application_error(-20001,'Please specify the target file in directory '||target);
            END IF;
            source_file := bfilename(target, keyword);
            BEGIN
                dbms_lob.fileopen(source_file);
            EXCEPTION WHEN OTHERS THEN
                raise_application_error(-20001,sqlerrm||' (Directory:"'||target||'"  File:"'||keyword||'")');
            END;
            dbms_lob.createtemporary(content, true);
            dbms_lob.loadblobfromfile(content,source_file,least(1048576,dbms_lob.getlength(source_file)),dest_offset,src_offset);
            dbms_lob.fileclose(source_file);
        END IF;
        ctx := blob2clob(content);
        dest_offset := 1;
        FOR i IN 1..100 LOOP
            src_offset := dbms_lob.instr(ctx,chr(10),dest_offset);
            EXIT WHEN nvl(src_offset,0) <= 0;
            tab.extend;
            tab(i):=trim(chr(13) from dbms_lob.substr(ctx,least(2000,src_offset-dest_offset),dest_offset));
            dest_offset := src_offset + 1;
        END LOOP;
        dbms_lob.freetemporary(ctx);
        OPEN c FOR SELECT ROWNUM "#",a.* FROM TABLE(tab) a;
    ELSE
        IF is_url THEN
            asser_credential;
            target := assert_url(target);
            SELECT JSON_ARRAYAGG(JSON_OBJECT(OBJECT_NAME,BYTES,CHECKSUM,
                                     'Created' VALUE TO_CHAR(CREATED,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                                     'LastModified' VALUE TO_CHAR(LAST_MODIFIED,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'))
                                RETURNING CLOB)
            INTO  CTX
            FROM (
                SELECT * 
                FROM DBMS_CLOUD.LIST_OBJECTS(credential,target) 
                WHERE  &filter 
                ORDER BY LAST_MODIFIED DESC
                FETCH FIRST decode(op,'list',100,1024) ROWS ONLY);
        ELSE
            target := assert_dir(target);
            SELECT JSON_ARRAYAGG(JSON_OBJECT(OBJECT_NAME,BYTES,CHECKSUM,
                                     'Created' VALUE TO_CHAR(CREATED,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                                     'LastModified' VALUE TO_CHAR(LAST_MODIFIED,'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'))
                                RETURNING CLOB)
            INTO  CTX
            FROM (
                SELECT * 
                FROM  DBMS_CLOUD.LIST_FILES(target) 
                WHERE &filter 
                ORDER BY LAST_MODIFIED DESC
                FETCH FIRST decode(op,'list',100,1024) ROWS ONLY);
        END IF;

        IF op NOT IN ('list') THEN
            SELECT *
            BULK   COLLECT INTO T1
            FROM   JSON_TABLE(ctx,'$[*]' columns OBJECT_NAME VARCHAR2(1000));
        END IF;
    END IF;

    IF op in('copy','move') THEN
        IF is_url THEN
            dest := assert_dir(dest);
            IF &f=0 THEN
                DBMS_CLOUD.BULK_DOWNLOAD (
                    credential_name => credential,
                    location_uri    => target,
                    directory_name  => dest,
                    regex_filter    => keyword,
                    format          => JSON_OBJECT('priority' value 'HIGH'));
            ELSE
                FOR i IN 1..t1.COUNT LOOP
                    DBMS_CLOUD.GET_OBJECT(credential,target,dest,file_name=>t1(i));
                END LOOP;
            END IF;
        ELSE
            asser_credential;
            dest := assert_url(dest);
            IF &f=0 THEN
                DBMS_CLOUD.BULK_UPLOAD(
                    credential_name => credential,
                    location_uri    => dest,
                    directory_name  => target,
                    regex_filter    => keyword,
                    format          => JSON_OBJECT('priority' value 'HIGH'));
            ELSE
                FOR i IN 1..t1.COUNT LOOP
                    DBMS_CLOUD.PUT_OBJECT(credential,target,dest,file_name=>t1(i));
                END LOOP;
            END IF;
        END IF;
    END IF;

    IF op in('delete','move') THEN
        IF is_url THEN
            IF &f=0 THEN
                DBMS_CLOUD.BULK_DELETE(credential,target,keyword);
            ELSE
                FOR i IN 1..t1.COUNT LOOP
                    DBMS_CLOUD.DELETE_OBJECT(credential,trim('/' from target)||'/'||t1(i));
                END LOOP;
            END IF;
        ELSE
            FOR i IN 1..t1.COUNT LOOP
                DBMS_CLOUD.DELETE_FILE(target,t1(i));
            END LOOP;
        END IF;
    END IF;

    IF c IS NULL THEN
        OPEN c FOR
            SELECT * 
            FROM   JSON_TABLE(ctx,'$[*]' COLUMNS
                       OBJECT_NAME VARCHAR2(256),
                       BYTES INT,
                       CHECKSUM VARCHAR2(64),
                       Created VARCHAR2(40),
                       LastModified VARCHAR2(40))
            WHERE  ROWNUM<=100;
    END IF;
    :c := c;
END;
/
