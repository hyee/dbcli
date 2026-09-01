/*[[Parsing Input IceBerg metadata to generate DDL statement of external table

    Usage: @@NAME {<dir_name>} {<iceberg metadata JSON> | <metadata file path>}

    <dir_name>   : The directory object name. It is used as
                   1) the directory(BFILE) to load the metadata file when the
                      second argument is a file name without path
                   2) the target external table name
                   3) the default directory for BigData connector
                   4) the credential.name in ACCESS PARAMETERS
                   5) the credential.schema defaults to CURRENT_SCHEMA

    The generated DDL follows the same template as DBMS_CLOUD output:
    CREATE TABLE "<owner>"."<dir_name>" (<cols>)
    ORGANIZATION EXTERNAL
    ( TYPE ORACLE_BIGDATA
      DEFAULT DIRECTORY "<dir_name>"
      ACCESS PARAMETERS
      ( com.oracle.bigdata.credential.schema="<owner>"
        com.oracle.bigdata.credential.name="<dir_name>"
        com.oracle.bigdata.access_protocol=iceberg
        com.oracle.bigdata.csv.rowformat.fields.terminator='|'
        com.oracle.bigdata.trimspaces=notrim
        com.oracle.bigdata.fileformat=parquet
      )
    )
    LOCATION ('iceberg://<metadata-file>')
    REJECT LIMIT 0
    <metadata>   : It can be
                   1) the Iceberg metadata JSON text, which starts with '{'
                   2) a metadata file name or full path. If the path contains
                      '/', the directory object is resolved automatically
                      (like oracle/tracefile.lua does): search DBA_DIRECTORIES
                      by the directory path, or create a temporary directory
                      DBCLI_ICEBERG_DIR(on demand) and drop it afterwards.
                   The metadata JSON can be
                   1) the content of v<N>.metadata.json
                   2) a JSON object with the schema part only:
                      {"current-schema-id":0,"schemas":[{"schema-id":0,"fields":[...]}]}
                   3) a single schema object: {"schema-id":0,"fields":[...]}

    The DDL LOCATION clause is the metadata file URL prefixed with the
    "iceberg:" protocol. The engine resolves parquet files by following the
    manifest chain starting from this metadata file:
        metadata -> manifest-list -> manifest -> data_files.file_path
    The metadata URL is resolved in this order:
        1) the "metadata-file" field of the LAST entry of the top-level
           "metadata-log" array (entries are previous metadata files ordered
           from old to new, so the last one is the latest; this is the
           standard Iceberg v1/v2 metadata layout, and the same value
           appears in e.g. Glue/Hive REST Parameters.metadata_location)
        2) the raw path passed as the 2nd argument (when it is a file path)
        3) NULL when none of the above is available

    The column definition is generated with the same type mapping as Oracle's
    internal implementation(SYS.KUBSBD$ICEBERG, see also GET_MAPPED_SCHEMA and
    ICEBERG_DATA_TYPE_MAPPING in 19.30.plsql dump):
        boolean->NUMBER(1)    int->NUMBER(10)        long->NUMBER(20)
        float->BINARY_FLOAT   double->BINARY_DOUBLE  decimal(P[,S])->NUMBER(P[,S])
        date->DATE            time->VARCHAR2(20 BYTE) timestamp->TIMESTAMP(9)
        timestamptz->TIMESTAMP(9) WITH TIME ZONE     string/uuid->VARCHAR2(4000 BYTE)
        fixed[N]/binary->RAW(2000)                   struct/list/map->VARCHAR2(4000)
    NOTE: fixed/binary are mapped to RAW(2000) as in 23.1/26.x official
    implementation(19c official maps them to VARCHAR2(4000 BYTE)).
    All the APIs used here(PL/SQL JSON object model JSON_OBJECT_T/JSON_ARRAY_T/
    JSON_ELEMENT_T, associative array constructor initialization, TREAT,
    DBMS_ASSERT.ENQUOTE_NAME, DBMS_LOB.LOADCLOBFROMFILE) are available in
    Oracle 12.2+, thus this script can be executed on Oracle 19c / ADB 19c
    without any 21c+ feature.

    Examples:
        @@NAME OBJ1 '{"current-schema-id":0,"schemas":[{"schema-id":0,"fields":[{"id":1,"name":"id","type":"long"},{"id":2,"name":"name","type":"string"}]}]}'
        @@NAME OBJ1 v1.metadata.json
        @@NAME OBJ1 /u01/iceberg/t1/metadata/v1.metadata.json
        -- the last one resolves the directory automatically and may require
        -- the "create directory" privilege

    --[[
        @ARGS: 2
    --]]
]]*/

DECLARE
    FUNCTION generate_ddl(dir_name VARCHAR2, metadata CLOB, meta_path VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
        meta          json_object_t;
        schemas       json_array_t;
        fields        json_array_t;
        cur_schema_id VARCHAR2(20);
        cols          CLOB := '';
        location      VARCHAR2(4000);
        found         BOOLEAN := FALSE;
        TYPE dmap_t IS TABLE OF VARCHAR2(64) INDEX BY VARCHAR2(64);
        dmap CONSTANT dmap_t := dmap_t(
            'boolean'     => 'NUMBER(1)',
            'int'         => 'NUMBER(10)',
            'long'        => 'NUMBER(20)',
            'float'       => 'BINARY_FLOAT',
            'double'      => 'BINARY_DOUBLE',
            'decimal'     => 'NUMBER',
            'date'        => 'DATE',
            'time'        => 'VARCHAR2(20 BYTE)',
            'timestamp'   => 'TIMESTAMP(9)',
            'timestamptz' => 'TIMESTAMP(9) WITH TIME ZONE',
            'string'      => 'VARCHAR2(4000 BYTE)',
            'uuid'        => 'VARCHAR2(4000 BYTE)',
            'fixed'       => 'RAW(2000)',
            'binary'      => 'RAW(2000)',
            'struct'      => 'VARCHAR2(4000)',
            'list'        => 'VARCHAR2(4000)',
            'map'         => 'VARCHAR2(4000)');

        -- Iceberg type -> Oracle type, same as official ICEBERG_DATA_TYPE_MAPPING
        FUNCTION map_type(iceberg_type VARCHAR2) RETURN VARCHAR2 IS
            t     VARCHAR2(4000) := replace(iceberg_type, ' ', '');
            prec  VARCHAR2(10);
            scale VARCHAR2(10);
            m     VARCHAR2(64);
        BEGIN
            IF t LIKE 'decimal(%' THEN
                prec  := regexp_substr(t, '^decimal\((\d+)(,(\d+))?\)$', 1, 1, NULL, 1);
                scale := regexp_substr(t, '^decimal\((\d+)(,(\d+))?\)$', 1, 1, NULL, 3);
                IF scale IS NULL THEN
                    RETURN 'NUMBER(' || prec || ')';
                ELSE
                    RETURN 'NUMBER(' || prec || ',' || scale || ')';
                END IF;
            ELSIF t LIKE 'fixed[%' THEN
                RETURN 'RAW(2000)';
            ELSE
                m := dmap(t);
                IF m IS NULL THEN
                    raise_application_error(-20000,'Invalid iceberg type: ' || iceberg_type);
                END IF;
                RETURN m;
            END IF;
        END map_type;

        -- Quote column name safely, same as official BUILD_COL_NAME
        FUNCTION build_col_name(col VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN dbms_assert.enquote_name(
                trim(regexp_replace(
                    regexp_replace(col, '[[:cntrl:]]'),
                    '"|chr(13)|chr(10)')));
        END;
    BEGIN
        meta := json_object_t(metadata);

        -- LOCATION points to the metadata file URL itself (with 'iceberg:'
        -- protocol prefix in the final DDL). The metadata file URL is the
        -- entry point from which the engine follows the manifest chain
        -- (metadata -> manifest-list -> manifest -> data_files.file_path)
        -- to locate the actual parquet files.
        --
        -- The metadata URL is resolved in this order:
        --   1) the "metadata-file" field of the LAST entry of the top-level
        --      "metadata-log" array (each entry is a previous metadata file,
        --      ordered from old to new, so the last one is the latest; this
        --      is the standard Iceberg v1/v2 metadata layout)
        --   2) the raw path passed as the 2nd argument when it is a file
        --      path (NOT a JSON text)
        IF meta.has('metadata-log') THEN
            DECLARE
                log json_array_t := meta.get_array('metadata-log');
                e   json_object_t;
            BEGIN
                IF log.get_size > 0 THEN
                    e := TREAT(log.get(log.get_size - 1) AS json_object_t);
                    IF e.has('metadata-file') THEN
                        location := e.get_string('metadata-file');
                    END IF;
                END IF;
            END;
        END IF;
        IF location IS NULL AND meta_path IS NOT NULL AND
           NOT regexp_like(meta_path, '^\s*\{') THEN
            location := meta_path;
        END IF;

        -- Current schema id, defaults to the 1st schema
        IF meta.has('current-schema-id') THEN
            cur_schema_id := meta.get_string('current-schema-id');
        END IF;

        -- Locate the fields of the current schema
        IF meta.has('schemas') THEN
            schemas := meta.get_array('schemas');
            FOR i IN 0 .. schemas.get_size - 1 LOOP
                DECLARE
                    s json_object_t := TREAT(schemas.get(i) AS json_object_t);
                BEGIN
                    IF (cur_schema_id IS NULL AND i = 0) OR
                       (s.has('schema-id') AND
                        s.get_string('schema-id') = cur_schema_id) THEN
                        fields := s.get_array('fields');
                        found  := TRUE;
                    END IF;
                END;
                EXIT WHEN found;
            END LOOP;
        ELSIF meta.has('fields') THEN
            fields := meta.get_array('fields');
            found  := TRUE;
        END IF;

        IF NOT found THEN
            raise_application_error(-20000,
                'Cannot find any schema in the input metadata.');
        END IF;

        IF fields.get_size = 0 THEN
            raise_application_error(-20000,
                'The schema has no field, nothing to generate.');
        END IF;

        -- Build the column definition list
        FOR j IN 0 .. fields.get_size - 1 LOOP
            DECLARE
                f     json_object_t := TREAT(fields.get(j) AS json_object_t);
                cname VARCHAR2(4000);
                ctype VARCHAR2(4000);
                telem json_element_t;
            BEGIN
                cname := f.get_string('name');
                telem := f.get('type');
                IF telem.is_string THEN
                    -- json_string_t is not public until 21c, use the parent
                    -- object's get_string instead(12.2+, safe on 19c)
                    ctype := map_type(f.get_string('type'));
                ELSIF telem.is_object THEN
                    -- struct/map/list are mapped to VARCHAR2(4000)
                    -- same as official GET_MAPPED_SCHEMA
                    DECLARE
                        tj  json_object_t := TREAT(telem AS json_object_t);
                        ts  VARCHAR2(64) := tj.get_string('type');
                    BEGIN
                        IF ts IN ('map', 'struct', 'list') THEN
                            ctype := 'VARCHAR2(4000)';
                        ELSE
                            raise_application_error(-20000,
                                'Invalid iceberg type: ' || ts);
                        END IF;
                    END;
                ELSE
                    raise_application_error(-20000,
                        'Invalid iceberg type of column ' || cname);
                END IF;
                cols := cols || '   ' || build_col_name(cname) || ' ' || ctype ||
                        ',' || chr(10);
            END;
        END LOOP;

        -- Remove the trailing comma
        cols := regexp_replace(cols, ',\s*$', '');

        -- Assemble the CREATE TABLE ... ORGANIZATION EXTERNAL DDL
        RETURN 'CREATE TABLE <owner>.<table_name> (' || chr(10) || cols || chr(10) ||
               ')' || chr(10) ||
               'ORGANIZATION EXTERNAL' || chr(10) ||
               '(' || chr(10) ||
               '  TYPE ORACLE_BIGDATA' || chr(10) ||
               '  DEFAULT DIRECTORY ' || build_col_name(dir_name) || chr(10) ||
               '  ACCESS PARAMETERS' || chr(10) ||
               '  (' || chr(10) ||
               '    com.oracle.bigdata.credential.schema="<owner>"' || chr(10) ||
               '  --com.oracle.bigdata.credential.name=' || build_col_name(dir_name) || chr(10) ||
               '    com.oracle.bigdata.access_protocol=iceberg' || chr(10) ||
               '    com.oracle.bigdata.buffersize=10240' || chr(10) ||
               '    com.oracle.bigdata.compressiontype=detect' || chr(10) ||
               '    com.oracle.bigdata.characterset="UTF-8"' || chr(10) ||
               '    com.oracle.bigdata.dateformat=auto' || chr(10) ||
               '    com.oracle.bigdata.timestampformat=auto' || chr(10) ||
               '    com.oracle.bigdata.timestamptzformat=auto' || chr(10) ||
               '    com.oracle.bigdata.timestampltzformat=auto' || chr(10) ||
               '    com.oracle.bigdata.ignoreblanklines=true' || chr(10) ||
               '    com.oracle.bigdata.csv.rowformat.fields.terminator=' || q'['|']' || chr(10) ||
               '    com.oracle.bigdata.trimspaces=notrim' || chr(10) ||
               '    com.oracle.bigdata.fileformat=parquet' || chr(10) ||
               '  )' || chr(10) ||
               ')' || chr(10) ||
               'LOCATION' || chr(10) ||
               '(' || chr(10) ||
               '   --the real data file location is defined at $.snapshots[*].manifest-list (.avro file)'|| chr(10) ||
               '  ' || CASE WHEN location IS NULL THEN 'NULL'
                            ELSE dbms_assert.enquote_literal('iceberg:' || location)
                       END || chr(10) ||
               ')' || chr(10) ||
               'REJECT LIMIT UNLIMITED';
    END generate_ddl;

    -- Load a metadata file into CLOB, the directory object is resolved the
    -- same way as oracle/tracefile.lua does:
    --   1) if the path contains '/', split it into dir + file
    --   2) find the matched directory object in dba_directories by dir path
    --   3) if none, create a temporary directory DBCLI_ICEBERG_DIR and drop
    --      it after reading(drop on exception too)
    --   if the path has no '/', use the <dir_name> directory object directly
    FUNCTION load_metadata(path VARCHAR2, dir_name VARCHAR2) RETURN CLOB IS
        f     VARCHAR2(4000) := path;
        dir   VARCHAR2(200);
        tmp   VARCHAR2(4000);
        bf    BFILE;
        meta  CLOB;
        csid  PLS_INTEGER := 0;
        lang  PLS_INTEGER := 0;
        warn  PLS_INTEGER := 0;
        len   PLS_INTEGER;
        flag  PLS_INTEGER := -1;
        doff  PLS_INTEGER := 1;  -- dest_offset of loadclobfromfile(IN OUT)
        soff  PLS_INTEGER := 1;  -- src_offset
        PROCEDURE drop_dir IS
        BEGIN
            EXECUTE IMMEDIATE 'DROP DIRECTORY DBCLI_ICEBERG_DIR';
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    BEGIN
        dir := regexp_substr(f, '.*[\\/]');
        IF dir IS NOT NULL THEN
            -- full path: split and resolve the directory object
            f   := substr(f, length(dir) + 1);
            tmp := dir;
            BEGIN
                EXECUTE IMMEDIATE replace(q'[
                    SELECT MAX(directory_name)
                    FROM   dba_directories
                    WHERE  lower('@t') LIKE lower(directory_path) || '%'
                    AND    length('@t') - length(directory_path) < 2]', '@t', tmp)
                INTO dir;
            EXCEPTION WHEN OTHERS THEN
                SELECT MAX(directory_name)
                INTO   dir
                FROM   all_directories
                WHERE  lower(tmp) LIKE lower(directory_path) || '%'
                AND    length(tmp) - length(directory_path) < 2;
            END;
            IF dir IS NULL THEN
                EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY DBCLI_ICEBERG_DIR AS '''
                                  || tmp || '''';
                dir  := 'DBCLI_ICEBERG_DIR';
            END IF;
            -- directory resolved(temporary dir will be dropped after reading)
            flag := 0;
        ELSE
            -- file name only: use the directory object passed by user
            f := path;
            IF dir_name IS NULL OR dir_name = '' THEN
                raise_application_error(-20000,
                    'Please input a directory object name as the 1st argument.');
            END IF;
            dir := dir_name;
        END IF;

        flag := 1;
        bf   := bfilename(dir, f);
        flag := 2;
        dbms_lob.fileopen(bf);
        len := dbms_lob.getlength(bf);
        IF len = 0 THEN
            dbms_lob.fileclose(bf);
            IF flag = 0 THEN drop_dir; END IF;
            raise_application_error(-20000,
                'The metadata file ' || f || ' is empty.');
        END IF;

        dbms_lob.createtemporary(meta, TRUE, dbms_lob.session);
        -- one shot BFILE -> CLOB, no 32K loop limitation
        dbms_lob.loadclobfromfile(meta, bf, len, doff, soff, csid, lang, warn);
        dbms_lob.fileclose(bf);
        IF flag = 0 THEN drop_dir; END IF;
        RETURN meta;
    EXCEPTION
        WHEN OTHERS THEN
            IF bf IS NOT NULL AND dbms_lob.fileisopen(bf) = 1 THEN
                dbms_lob.fileclose(bf);
            END IF;
            drop_dir;
            IF flag = -1 THEN
                raise_application_error(-20000,
                    'You cannot access view dba_directories, please grant the relative access right!');
            ELSIF flag = 1 THEN
                raise_application_error(-20000,
                    'File ' || f || ' under directory ' || nvl(tmp, dir) ||
                    ' does not exist!');
            ELSE
                raise_application_error(-20000,
                    regexp_substr(dbms_utility.format_error_stack,
                                  '([A-Z]+\-\d+)[^' || chr(10) || ']+') ||
                    '[dir="' || nvl(tmp, dir) || '" file="' || f || '"]');
            END IF;
            RAISE;
    END load_metadata;
BEGIN
    DECLARE
        l_ddl VARCHAR2(32767);
    BEGIN
        IF regexp_like('&V2', '^\s*\{') THEN
            -- The 2nd argument is the metadata JSON text itself
            l_ddl := generate_ddl('&V1', to_clob('&V2'), '&V2');
        ELSE
            -- The 2nd argument is a metadata file path/name
            l_ddl := generate_ddl('&V1', load_metadata('&V2', '&V1'), '&V2');
        END IF;
        dbms_output.put_line(l_ddl);
    END;
END;
