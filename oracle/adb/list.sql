/*[[
    List files in Cloud Object Storage or Oracle directory. Usage: $$NAME {<directory>|{[<credential>] <URL>}} [<keyword>|-f"<filter>"] 
    <credential>: Optional if the default credential is defined via 'set credential'
    <URL>       : The Object Storage directory URL. can be '/<sub_files>' if the default URL is defined via 'set bucket'
    <directory> : Shoule be found in view all_directories
    <keyword>   : Can be:
                  1) the "LIKE" pattern that supports wildchars '%' and '_'
                  2) the 'REGEXP_LIKE' pattern
                  3) customized the WHERE clause by -f"<filter>"
    -object     : sort result by object_name
    -created    : sort result by created
    -asc        : sort in asc orderd
    --[[
        @ARGS: 1
        @CHECK_ACCESS_CLOUD: DBMS_CLOUD={}
        &filter: {default={regexp_like(object_name,$KEYWORD$,'i')} f={}}
        &f     : default={0} f={1}
        &op    : default={list} delete={delete} copy={copy} move={move} unload={unload} view={view} ddl={ddl}
        &ops   : default={} delete={ deleted} copy={ copied} move={ to be moved} unload={ unloaded}
        &pubs  : default={,"multipart":true,"maxfilesize":104857600}
        &typ   : json={"json"&pubs} parquet={"parquet"} parquet={"parquet"} csv={"csv","header":true,"escape":true&pubs} xml={"xml"&pubs} dmp={"datapump","compression":"medium","version":"compatible"}
        &gzip  : default={} gzip={,"compression":"gzip"}
        &sort  : default={last_modified} object={object_name} created={created}
        &asc   : default={desc} asc={}
    --]]
]]*/

var c refcursor "List of recent 100 matched objects&ops"
col bytes for tmb
set feed off
DECLARE
    C            SYS_REFCURSOR;
    op           VARCHAR2(10) := :op;
    keyword      VARCHAR2(32767) := COALESCE(:V4, :V3, :V2);
    cols         VARCHAR2(32767);
    stmt         VARCHAR2(32767);
    dest         VARCHAR2(1000);
    target       VARCHAR2(1000) := CASE WHEN instr(nvl(:V2,'x'),'/')=0 THEN :V1 ELSE NVL(:V2,:V1) END;
    credential   VARCHAR2(1000) := CASE WHEN :V1=target THEN :credential ELSE :V1 END;
    ext          VARCHAR2(128);
    base_owner   VARCHAR(128);
    base_table   VARCHAR2(256):=upper(CASE WHEN target=:V1 THEN :V2 WHEN keyword=:V3 THEN '' ELSE :V3 END);
    is_url1      BOOLEAN := FALSE;
    is_url2      BOOLEAN := FALSE;
    ctx          CLOB;
    content      BLOB;
    OID          INT;
    pos          INT;
    dest_offset  INTEGER := 1;
    src_offset   INTEGER := 1;
    lob_csid     NUMBER  := dbms_lob.default_csid;
    lang_context INTEGER := dbms_lob.default_lang_ctx;
    warning      INTEGER;
    source_file  BFILE;
    t1           SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    tab          SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

    FUNCTION BLOB2CLOB(ctx IN OUT NOCOPY BLOB) RETURN CLOB IS
        v_clob CLOB;
        v_len  PLS_INTEGER :=dbms_lob.getlength(ctx);
    BEGIN
        IF v_len = 0 THEN
            RETURN empty_clob();
        END IF; 
        dest_offset := 1;
        src_offset  := 1;
        dbms_lob.createtemporary(v_clob, TRUE);
        dbms_lob.ConvertToCLOB(v_clob,
                               ctx,
                               v_len,
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
        IF instr(d, '/') > 0 AND instr(d,'https://')=0 THEN
            IF :objbucket IS NULL THEN
                raise_application_error(-20001, 'Please define the default bucket by "set bucket" when the URL is a relative path.');
            END IF;
            d := trim(trailing '/' from :objbucket)||'/'|| trim(leading '/'  from d);
        END IF;
        IF instr(nvl(d, 'x'), 'http') != 1 THEN
            raise_application_error(-20001, 'Invalid Object Storage URL: ' || d);
        END IF;
        RETURN d;
    END;

    PROCEDURE describe_cols IS
    BEGIN
        cols := '';
        FOR r IN(
            SELECT '"'||column_name||'" '||
                   CASE 
                       WHEN DATA_TYPE IN('CHAR',
                                          'VARCHAR',
                                          'VARCHAR2',
                                          'NCHAR',
                                          'NVARCHAR',
                                          'NVARCHAR2',
                                          'RAW') --
                       THEN DATA_TYPE||'(' || DECODE(CHAR_USED, 'C', CHAR_LENGTH,DATA_LENGTH) || DECODE(CHAR_USED, 'C', ' CHAR') || ')' --
                       WHEN DATA_TYPE = 'NUMBER' --
                       THEN (CASE WHEN nvl(DATA_scale, DATA_PRECISION) IS NULL THEN DATA_TYPE
                                  WHEN DATA_scale > 0 THEN DATA_TYPE||'(' || NVL(''||DATA_PRECISION, '38') || ',' || DATA_SCALE || ')'
                                  WHEN DATA_PRECISION IS NULL AND DATA_scale=0 THEN 'INTEGER'
                                  ELSE DATA_TYPE||'(' || DATA_PRECISION ||')' END) 
                       WHEN DATA_TYPE='DATE' THEN
                            'TIMESTAMP(0)'
                       ELSE DATA_TYPE 
                   END c
            FROM ALL_TAB_COLUMNS
            WHERE owner=base_owner
            AND   table_name=base_table
            ORDER BY column_id) LOOP
            cols := cols||chr(10)||'        '||r.c||',';
        END LOOP;
        cols := trim(',' from cols);
    END;
BEGIN
    dbms_output.enable(null);
    IF op IN ('copy', 'move') THEN
        IF :V4 IS NOT NULL THEN
            dest       := :v3;
            target     := :v2;
            credential := :V1;
        ELSIF :V3 IS NOT NULL OR &f = 1 AND :V2 IS NOT NULL THEN
            dest       := :v2;
            target     := :v1;
            credential := :credential;
        ELSIF :V2 IS NOT NULL AND instr(:V1,'/')>0 THEN
            keyword    := '.';
            dest       := :v2;
            target     := :v1;
            credential := :credential;
        ELSE
            raise_application_error(-20001, 'Arguments: [<credential>] <source> <destination> <keyword>');
        END IF;
    END IF;

    IF &f = 0 AND op not in ('view','ddl') THEN
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
        IF target LIKE '%/' THEN
            target := target || 'unload';
        ELSIF NOT is_url1 THEN
            target := target||':1.dmp';
        END IF;
        dbms_cloud.export_data(credential_name => credential,
                               file_uri_list   => target,
                               query           => keyword,
                               format          => '{"type":&typ &gzip}',
                               operation_id    => OID);
        SELECT JSON_ARRAYAGG(JSON_OBJECT('OBJECT_NAME' VALUE FILE_URI_LIST,
                                         'CHECKSUM' VALUE STATUS,
                                         'Created' VALUE TO_CHAR(START_TIME, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                                         'Last_Modified' VALUE TO_CHAR(UPDATE_TIME, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')))
        INTO   CTX
        FROM   USER_LOAD_OPERATIONS
        WHERE  ID = OID;
    ELSIF op in ('view','ddl') THEN
        c := NULL;
        dest:= lower(CASE WHEN is_url1 then target else :V2 end);
        IF lower(base_table)=dest THEN
            base_table := null;
        END IF;
        ext := regexp_substr(dest,'[^.]+$');
        IF lower(keyword) IN('csv','json','xml','dmp','orc','avro','parquet') THEN
            keyword := lower(keyword);
            dest    := keyword;
        ELSIF nvl(base_table,upper(keyword))=upper(keyword) AND lower(keyword)!=dest THEN
            base_table := upper(keyword);
            keyword    := null;
        END IF;
        dest := regexp_substr(dest,'(csv|json|xml|parquet|avro|orc|dmp)(.gz|.gzip|.bz2|.z|.zl|.zip)?$',1,1,'i',1);
        IF base_table IS NOT NULL THEN
            base_table:=replace(base_table,'"');
            IF keyword IS NULL THEN
                IF dest IS NOT NULL THEN
                    keyword := dest;
                ELSE
                    raise_application_error(-20001,'Unsupport data type: '||ext);
                END IF;
            END IF;
            base_owner := nvl(trim('.' from regexp_substr(base_table,'^[^.]+\.')),sys_context('userenv','CURRENT_SCHEMA'));
            base_table := regexp_substr(base_table,'[^.]+$');
            IF base_table IS NULL THEN
                raise_application_error(-20001,'Please specified the based table name.');
            END IF;
            dest := base_owner||'.'||base_table;
            SELECT MAX(OWNER),MAX(TABLE_NAME)
            INTO   base_owner,base_table
            FROM   all_tables
            WHERE  owner=base_owner AND table_name=base_table;

            IF base_table IS NULL THEN
                raise_application_error(-20001,'Cannot find target table: '||dest);
            END IF;
            describe_cols;
            IF is_url1 THEN
                IF target LIKE '%/' THEN
                    raise_application_error(-20001, 'Target must be a file: ' || target);
                END IF;
            ELSE
                dest := :V2;
            END IF;

            stmt :='
                BEGIN
                    DBMS_CLOUD.CREATE_EXTERNAL_TABLE(
                        table_name      => ''<TABLE_NAME>'',
                        credential_name => '''||CASE WHEN is_url1 THEN credential END||''',
                        file_uri_list   => '''||target||CASE WHEN NOT is_url1 THEN ':'||dest END||''',
                        format          => ''{
                            "rejectlimit":"unlimited",#FORMAT#
                            '||case when ext!=keyword then '"compression":"auto",' END||'
                            "type":"'||case when keyword='dmp' then 'datapump' when keyword in('json','xml') then 'csv' else keyword end||'"}'',
                        column_list     => '''||CASE WHEN keyword IN('json','xml') THEN 'doc CLOB' ELSE cols END||''',
                        field_list      => '''||CASE WHEN keyword IN('json','xml') THEN 'doc CHAR(10000000)' END||'''
                    );
                END;';
            IF keyword IN('csv','json','xml') THEN
                stmt := replace(stmt,'#FORMAT#','
                            '||CASE WHEN keyword='csv' THEN '"skipheaders":"1",' END||' 
                            "conversionerrors":"store_null",
                            "delimiter":"'||CASE WHEN keyword='csv' THEN ',' ELSE 'DETECTED NEWLINE' END||'", 
                            "dateformat":"auto",
                            "timestampformat":"auto", 
                            "timestampltzformat":"auto", 
                            "timestamptzformat":"auto", 
                            "truncatecol":"true", 
                            "ignoreblanklines":"true", 
                            "ignoremissingcolumns":"true",
                            "blankasnull":"true",
                            "removequotes":"false",
                            "escape":"true",
                            "trimspaces":"rtrim",');
            ELSE
                stmt := replace(stmt,'#FORMAT#');
            END IF;

            IF op='ddl' THEN
                OPEN  c FOR
                    SELECT regexp_replace(stmt,chr(10)||'\s{16}',chr(10)) statement FROM dual;
            END IF;

            stmt :='SELECT A.*'||chr(10)||'FROM EXTERNAL((#COLS#)'||chr(10)||
                   '     TYPE ORACLE_#TYPE# '||chr(10)||
                   '     ACCESS PARAMETERS(#PARAM#)'||chr(10)||
                   '     LOCATION ('||CASE WHEN is_url1 THEN ''''||target||'''' ELSE target||':'''||dest||'''' END||')'||chr(10)||
                   '     REJECT LIMIT UNLIMITED)';
            IF keyword NOT IN('csv','dmp') THEN
                --https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle_bigdata_access_driver.html
                stmt := replace(replace(replace(stmt,
                    '#COLS#',CASE WHEN keyword IN('json','xml') THEN 'doc CLOB' ELSE cols END),
                    '#TYPE#','BIGDATA'),
                    '#PARAM#',CASE WHEN is_url1 THEN 'com.oracle.bigdata.credential.name='||credential END||'
                    com.oracle.bigdata.csv.skip.header=1
                    com.oracle.bigdata.fileformat='||CASE WHEN keyword IN('json','xml') THEN 'textfile' when keyword='dmp' THEN 'datapump' ELSE keyword END||'
                    com.oracle.bigdata.buffersize=2048
                    com.oracle.bigdata.compressiontype='||CASE WHEN ext in('csv','xml','son') THEN 'none' ELSE 'detect' END||'
                    com.oracle.bigdata.csv.rowformat.fields.terminator='''||CASE WHEN keyword IN('json','xml') THEN '\n' ELSE ',' END||'''
                    com.oracle.bigdata.dateformat=auto
                    com.oracle.bigdata.timestampformat=auto
                    com.oracle.bigdata.timestampltzformat=auto
                    com.oracle.bigdata.timestamptzformat=auto
                    com.oracle.bigdata.truncatecol=true
                    com.oracle.bigdata.removequotes=true
                    com.oracle.bigdata.ignoremissingcolumns=true
                    com.oracle.bigdata.ignoreblanklines=true
                    com.oracle.bigdata.blankasnull=true
                    com.oracle.bigdata.trimspaces=rtrim');
                IF keyword='json' THEN
                    stmt := stmt || ' p,'||chr(10)||'JSON_TABLE(p.doc,''$'' COLUMNS ('||cols||')) A';
                ELSIF keyword='xml' THEN
                    stmt := stmt || ' p,'||chr(10)||'XMLTABLE(p.doc PASSING ''/*'' COLUMNS '||regexp_replace(cols,'"(.*?)"([^,]+)','"\1"\2 path ''\1''')||') A';
                ELSE
                    stmt := stmt || ' a';
                END IF;
            ELSIF keyword='dmp' THEN
                --https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle_datapump-access-driver.html
                stmt := replace(replace(replace(stmt,
                    '#COLS#',cols),
                    '#TYPE#','DATAPUMP'),
                    '#PARAM#',CASE WHEN is_url1 THEN' CREDENTIAL '||credential END||' NOLOGFILE ')||' a';
            ELSE
                --https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle_loader-access-driver.html
                stmt := replace(replace(stmt,'#TYPE#','LOADER'),
                    '#PARAM#','RECORDS '||CASE WHEN ext not in('csv','xml','son') THEN 'COMPRESSION DETECT' END
                    ||CASE WHEN is_url1 THEN ' CREDENTIAL '||credential END
                    ||' DELIMITED BY DETECTED NEWLINE NOLOGFILE NOBADFILE NODISCARDFILE READSIZE=10000000 DISABLE_DIRECTORY_LINK_CHECK IGNORE_BLANK_LINES
                     #PARAM#');
                IF keyword='csv' THEN
                    --badfile, byteordermark, characterset, column, cloud_params, compression, credential, 
                    --credential_name, credential_schema, data, delimited, discardfile, dnfs_enable, 
                    --dnfs_disable, disable_directory_link_check, escape, field, fields, fixed, 
                    --io_options, file_uri_list, filename_columns, ignore_blank_lines, ignore_header, 
                    --load, logfile, language, nodiscardfile, nobadfile, nologfile, date_cache, dnfs_readbuffers, 
                    --preprocessor, preprocessor_timeout, readsize, string, skip, territory, variable, 
                    --validate_table_data, xmltag
                    stmt := replace(replace(stmt,'#COLS#',cols),
                        '#PARAM#',q'~IGNORE_HEADER=1 FIELDS TERMINATED BY ',' CSV WITH EMBEDDED
                        DATE_FORMAT DATE MASK 'auto' 
                        DATE_FORMAT TIMESTAMP MASK 'auto' 
                        DATE_FORMAT TIMESTAMP WITH LOCAL TIME ZONE 'auto' 
                        DATE_FORMAT TIMESTAMP WITH TIME ZONE 'auto'
                        CONVERT_ERROR STORE_NULL
                        TRUNCATE_COLUMNS MISSING FIELD VALUES ARE NULL NULLIF=BLANKS RTRIM~')||' A';
                ELSE
                    stmt := replace(replace(stmt,'#COLS#','doc CLOB'),
                        '#PARAM#','FIELDS TERMINATED BY ''NEWLINE''  NOTRIM (doc CHAR(10000000))')||' p,'||chr(10);
                    IF keyword='json' THEN
                        stmt := stmt || 'JSON_TABLE(p.doc,''$'' COLUMNS ('||cols||')) A';
                    ELSE
                        stmt := stmt || 'XMLTABLE(p.doc PASSING ''/*'' COLUMNS '||regexp_replace(cols,'"(.*?)"([^,]+)','"\1"\2 path ''\1''')||') A';
                    END IF;
                END IF;
            END IF;
            stmt := stmt||chr(10)||'WHERE ROWNUM<=100';

            IF op='view' THEN
                dbms_output.put_line(stmt);
                dbms_output.put_line(rpad('*',80,'*'));
                OPEN c FOR stmt;
            END IF;
        ELSIF op='ddl' AND dest in('json','xml') THEN
            stmt :='
                BEGIN
                    DBMS_CLOUD.CREATE_EXTERNAL_TABLE(
                        table_name      => ''<TABLE_NAME>'',
                        credential_name => '''||CASE WHEN is_url1 THEN credential END||''',
                        file_uri_list   => '''||target||CASE WHEN NOT is_url1 THEN ':'||dest END||''',
                        format          => ''{
                            "rejectlimit":"unlimited",
                            "conversionerrors":"store_null",
                            "delimiter":"DETECTED NEWLINE", 
                            "truncatecol":"true", 
                            "ignoreblanklines":"true", 
                            "ignoremissingcolumns":"true",
                            "blankasnull":"true",
                            "removequotes":"false",
                            "escape":"true",
                            "trimspaces":"rtrim",
                            '||case when ext!=dest then '"compression":"auto",' END||'
                            "type":"csv"}'',
                        column_list     => ''doc CLOB'',
                        field_list      => ''doc CHAR(10000000)''
                    );
                END;';
            OPEN c FOR 
                SELECT regexp_replace(stmt,chr(10)||'\s{16}',chr(10)) statement FROM DUAL;
        ELSIF op='ddl' AND dest in('orc','avro','parquet') THEN
            stmt := '
                BEGIN
                    DBMS_CLOUD.CREATE_EXTERNAL_TABLE(
                        table_name      => ''<TABLE_NAME>'',
                        credential_name => '''||credential||''',
                        file_uri_list   => '''||target||''',
                        format          =>''{"schema":"first","type":"'||dest||'","rejectlimit":"unlimited"}''
                    );
                END;';
            OPEN c FOR 
                SELECT regexp_replace(stmt,chr(10)||'\s{16}',chr(10)) statement FROM DUAL;
        ELSIF ext IN('orc','avro','parquet','zip','gzip','gz','z','zl','bz2','dmp') THEN
            raise_application_error(-20001, 'Please specify the based table to have the column info of target file.');
        ELSIF is_url1 THEN
            IF keyword IS NOT NULL THEN
                target := TRIM('/' FROM target) || '/' || keyword;
            ELSIF target LIKE '%/' THEN
                raise_application_error(-20001, 'Target must be a file: ' || target);
            END IF;
            content := dbms_cloud.get_object(credential_name => credential,
                                             object_uri      => target,
                                             startoffset     => 0,
                                             endoffset       => 1024*1024);
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
                    raise_application_error(-20001,SQLERRM || ' (Directory:"' || target || '"  File:"' || keyword || '")');
            END;
            dbms_lob.createtemporary(content, TRUE);
            dbms_lob.loadblobfromfile(content,
                                      source_file,
                                      least(2*1024*1024, dbms_lob.getlength(source_file)),
                                      dest_offset,
                                      src_offset);
            dbms_lob.fileclose(source_file);
        END IF;

        IF c IS NULL THEN
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
        END IF;
        dest := '';
    ELSE
        stmt := replace(replace(q'~
            SELECT JSON_ARRAYAGG(JSON_OBJECT(
                        OBJECT_NAME,
                        BYTES,
                        CHECKSUM,
                        'Created' VALUE TO_CHAR(CREATED, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM'),
                        'Last_Modified' VALUE TO_CHAR(LAST_MODIFIED, 'yyyy-mm-dd hh24:mi:ssxff3 TZH:TZM')) RETURNING CLOB)
            FROM   (SELECT *
                    FROM   DBMS_CLOUD.LIST_$OBJ$ :target)
                    WHERE  &filter
                    ORDER  BY &sort &asc FETCH FIRST decode(:op, 'list', 100, 1024) ROWS ONLY)~',
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
            IF t1.count=0 THEN
                t1.extend;
            END IF;
        END IF;

        IF is_url1 OR is_url2 THEN
            stmt := replace(replace(replace(q'~
                DECLARE
                    t1 SYS.ODCIVARCHAR2LIST:=:t1;
                BEGIN
                    FOR i IN 1..t1.COUNT LOOP
                        dbms_cloud.$OP2$_object(:credential,trim('/' from :target)||CASE WHEN t1(i) IS NOT NULL THEN '/'||t1(i) END,trim('/' from :dest)$OP3$);
                    END LOOP;
                END;~',
                '$OP1$',CASE is_url1 WHEN is_url2 THEN op WHEN true THEN 'download' ELSE 'upload' END),
                '$OP2$',CASE is_url1 WHEN is_url2 THEN op WHEN true THEN 'get'      ELSE 'put'    END),
                '$OP3$',CASE WHEN is_url1!=is_url2 THEN ',file_name=>t1(i)' 
                             WHEN regexp_like(CASE WHEN is_url1 THEN dest   ELSE target END,'\.\w+$') THEN '' 
                             ELSE q'[||'/'||t1(i)]' 
                        END);
            --dbms_output.put_line(credential||'|'||target||'|'||dest||'|'||keyword);
            EXECUTE IMMEDIATE stmt USING 
                t1,credential,
                CASE WHEN is_url1 THEN target ELSE dest   END,
                CASE WHEN is_url1 THEN dest   ELSE target END;
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
                FOR i IN 1 .. t1.COUNT LOOP
                    DBMS_CLOUD.DELETE_OBJECT(credential, TRIM('/' FROM target) ||CASE WHEN t1(i) IS NOT NULL THEN '/'||t1(i) END);
                END LOOP;
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
                              Last_Modified VARCHAR2(40))
            WHERE  ROWNUM <= 100;
    END IF;
    :c := c;
END;
/
