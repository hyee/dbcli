local env=env
local loader=env.class(env.data_loader)
function loader:ctor()
    self.db=env.getdb()
    self.command="load"
end

function loader.init_options(options)
    options.VARIABLE_FORMAT=':'
end

function loader.validate_options(options)
    local sql=[[
        SELECT NULL AS table_cat,
               t.owner AS table_schem,
               t.table_name AS table_name,
               t.column_name AS column_name,
               DECODE(substr(t.data_type, 1, 9),
                      'TIMESTAMP',DECODE(substr(t.data_type, 10, 1),'(',
                                  DECODE(substr(t.data_type, 19, 5), 'LOCAL', -102, 'TIME ', -101, 93),
                                  DECODE(substr(t.data_type, 16, 5), 'LOCAL', -102, 'TIME ', -101, 93)),
                      'INTERVAL ',DECODE(substr(t.data_type, 10, 3), 'DAY', -104, 'YEA', -103),
                      DECODE(t.data_type,
                             'BINARY_DOUBLE',101,
                             'BINARY_FLOAT',100,
                             'BFILE',-13,
                             'BLOB',2004,
                             'BOOLEAN',16,
                             'CHAR',1,
                             'CLOB',2005,
                             'COLLECTION',2003,
                             'DATE',93,
                             'FLOAT',6,
                             'JSON',2016,
                             'LONG',-1,
                             'LONG RAW',-4,
                             'NCHAR',-15,
                             'NCLOB',2011,
                             'NUMBER',2,
                             'NVARCHAR',-9,
                             'NVARCHAR2',-9,
                             'OBJECT',2002,
                             'OPAQUE/XMLTYPE',2009,
                             'RAW',-3,
                             'REF',2006,
                             'ROWID',-8,
                             'SQLXML',2009,
                             'UROWID',-8,
                             'VARCHAR2',12,
                             'VARRAY',2003,
                             'VECTOR',-105,
                             'XMLTYPE',2009,
                             DECODE((SELECT a.typecode
                                    FROM   ALL_TYPES a
                                    WHERE  a.type_name = t.data_type
                                    AND    ((a.owner IS NULL AND t.data_type_owner IS NULL) OR (a.owner = t.data_type_owner))),
                                    'OBJECT',2002,
                                    'COLLECTION',2003,
                                    1111))) AS data_type,
               t.data_type AS type_name,
               DECODE(t.data_precision,
                      NULL,DECODE(t.data_type,
                             'NUMBER',DECODE(t.data_scale, NULL, 38, 38),
                             DECODE(t.data_type,
                                    'CHAR',t.char_length,
                                    'VARCHAR',t.char_length,
                                    'VARCHAR2',t.char_length,
                                    'NVARCHAR2',t.char_length,
                                    'NCHAR',t.char_length,
                                    'NUMBER',0,
                                    t.data_length)),
                      t.data_precision) AS column_size,
               0 AS buffer_length,
               DECODE(t.data_type,
                      'NUMBER',DECODE(t.data_precision, NULL, DECODE(t.data_scale, NULL, 0, t.data_scale), t.data_scale),
                      t.data_scale) AS decimal_digits,
               10 AS num_prec_radix,
               DECODE(t.nullable, 'N', 0, 1) AS nullable,
               NULL AS remarks,
               t.data_default AS column_def,
               0 AS sql_data_type,
               0 AS sql_datetime_sub,
               t.data_length AS char_octet_length,
               t.column_id AS ordinal_position,
               DECODE(t.nullable, 'N', 'NO', 'YES') AS is_nullable,
               NULL AS SCOPE_CATALOG,
               NULL AS SCOPE_SCHEMA,
               NULL AS SCOPE_TABLE,
               NULL AS SOURCE_DATA_TYPE,
               'NO' AS IS_AUTOINCREMENT,
               NULL AS IS_GENERATEDCOLUMN
        FROM   all_tab_columns t
        WHERE  t.owner = '%s'
        AND    t.table_name ='%s'
        ORDER  BY table_schem, table_name, ordinal_position]]
    if options.object_owner and options.object_name then
        options.COLUMN_INFO_SQL=sql:trim():format(options.object_owner,options.object_name):gsub('\n        ','\n')
    end
end

return loader.new()