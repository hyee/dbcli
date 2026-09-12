local this=env.class()
local env=env

--Oracle -> Java date format pieces, applied in order: 'mm'->'MM' has to run before 'mi'->'mm',
--or the minutes that 'mi' just produced get matched again and turn into a month. pairs() over an
--inline table gave no order at all.
local ORA2JAVA={
    {'tzh:tzm','XXX'},
    {'tzr','XXX'},
    {'"',"'"},
    {'hh24','HH'},
    {'mon','MMM'},
    {'mm','MM'},
    {'mi','mm'},
}

local db_loader=java.require("com.opencsv.DBLoader",true)
local db_unloader=java.require("com.opencsv.DBUnloader",true)
--Command names and help texts live on the class rather than in a ctor: __onload runs against
--whatever this module returns, and it returns an instance created before any database is loaded.
this.load_command='load'
this.unload_command='unload'
this.load_helps=[[
        Load data from a CSV file into a table. usage: @@NAME <target_table> <src_csv> [SET options]

        Load options(case-insensitive):
        ===============================
        * show off|all|ddl|dml              : Show DDL/DML statement only and do not load CSV file:  ddl=show DDL only, dml=show DML only, all=show both DDL and DML
        * show_ddl|ddl                      : Show DDL only and do not load CSV file
        * show_dml|dml                      : Show DML only and do not load CSV file
        * create|new  off|on                : Show DDL and create table from CSV (default: off)
        * scan_rows|scanrows|scan <number>  : Used together with show/show_ddl/create, number of rows to scan for column names (default: 200)
        * column_size auto|actual|maximum   : Used together with show/show_ddl/create, Column size strategy (default: auto)
        * truncate on|off                   : Truncate table before loading (default: off)
        * errors <number>|-1                : Number of errors to allow before stopping, -1 as unlimited (default: 100)
        * batch_rows|batchrows <number>     : Number of rows to batch per insert (default: 2048)
        * bad_file|badfile auto|<filepath>  : Bad file path to store failed rows, auto as create at target csv folder(default: auto)
        * row_limit|rowlimit|limit <number> : Maximum number of rows to load (default: 0, unlimited)
        * report_mb|report <number>|-1      : Report progress every N MB loaded, -1 will suppress all messages (default: 8)
        * strict_mode|strict                : Strict number conversion to avoid overflow,such as number with decimal digits cannot cast to integer (default: off)
        * variable_format|var ?|:           : Variable format used in DML statement (default: ?)
        * platform auto|<platform>          : Database platform used to generate DDL/DML statement(default: auto)
                                              Avail options: mysql, oracle, pgsql, sqlserver, db2, mssql, postgresql
        * map_column_names|mapcolumnnames   : Map CSV column names to table column names,column mappings are case-insensitive.
          |mapnames (CSV_COL=TABLE_COL,...)   e.g.: map_column_names (ID=OBJECT_ID,NAME=OBJECT_NAME)
        
        CSV format options(case-insensitive):
        =====================================   
        * has_header|header on|off                                  : Whether the first row is a header row (default: on)
        * encoding <charset>                                        : Character encoding of CSV file (default: "")
        * delimiter <chars>                                         : CSV delimiter character (default: ,)
        * enclosure <chars>                                         : CSV enclosure character (default: ")
        * escape_char <char>                                        : CSV escape character to escape <enclosure> (default: \)
        * unescape_string|unescape                                  : Whether to unescape string "\n" and "\r" as CRLF for string column (default: on)
        * skip_rows|skiprows|skip <number>                          : Number of rows to skip if CSV rows is not started from the first row (default: 0)
        * skip_columns|skipcols (column1,column2,...)|off|auto      : Columns to be skipped from loading (default: auto)
        
        Timestamp format options:
        =============================
        * format :  Transform the blow 3 formats from Oracle format to Java format when values,if set as 'java' then no transformation will be taken.
                    When format is 'oracle'(default), the formats will be replaced into Java format:
                        * YYYY or yyyy or yy => yyyy or yy
                        * MON or mon         => MMMM
                        * MM or mm           => MM
                        * DD or dd           => dd
                        * HH or hh           => hh
                        * HH24 or hh24       => HH
                        * MI or mi           => mm
                        * SS or ss           => ss
                        * .ff or xff or xff3 => .SSS
                        * .ff5 or xff6       => .SSSSS
                        * TZH:TZM or tzh:tzm => XXX
                        * TZR or tzr         => XXX
                    You should set this option as 'java' firstly if you want to directly specify the Java formats.
        * date_format|dateformat|date <format>                      : Date format string (default: auto)
        * timestamp_format|timestampformat|timestamp <format>       : Timestamp format string (default: auto)
        * timestamptz_format|timestamptzformat|timestamptz <format> : Timestamp with timezone format string (default: auto)
        * locale <locale>                                           : Locale used to parse date/timestamp (default: "")
    ]]

this.unload_helps=[[
        Unload data from SELECT statement into CSV/SQL/JSON file. usage: @@NAME <savepath> <SQL_file>|"<SQL>" [SET <options>]

        Unload options(case-insensitive):
        ===============================
        * file_format|file_type|type        : Target file type, can be CSV, SQL or JSON (default:CSV)
        * batch_rows|batchrows <number>     : Number of rows prefeched from ResultSet (default: 2048)
        * row_limit|rowlimit|limit <number> : Maximum number of rows to unload (default: 0, unlimited)
        * report_mb|report <number>|-1      : Report progress every N MB loaded, -1 will suppress all messages (default: 8)
        * has_header|header on|off          : Whether the first row is a header row (default: on)
        * platform auto|<platform>          : Database platform used to generate DDL/DML statement(default: auto)
                                              Avail options: mysql, oracle, pgsql, sqlserver, db2, mssql, postgresql
        * map_column_names|mapcolumnnames   : Map CSV column names to table column names,column mappings are case-insensitive.
          |mapnames (CSV_COL=TABLE_COL,...)   e.g.: map_column_names (ID=OBJECT_ID,NAME=OBJECT_NAME)
        * skip_columns|skipcols             : Columns to be skipped from unloading (default: auto)
          (column1,column2,...)|off|auto    
        
        JSON format options(case-insensitive):
        =====================================
        * JSON_ROW_TYPE|JSON_TYPE OBJECT|ARRAY                      : Number of spaces to indent for JSON output (default: OBJECT)
                                                                      OBJECT: Each row is a JSON object.
                                                                      ARRAY: Each row is a JSON array,the first row is the header row(controlled by HASH_HEADER).
        * JSON_KEEP_NULLS|JSONKEEPNULLS ON|OFF                      : When JSON_ROW_TYPE is OBJECT, whether to keep null values in JSON output (default: on)
        * JSON_NULL_VALUE|JSONNULLVALUE <value>                     : JSON null value (default: null)
        
                                                                      CSV format options(case-insensitive):
        =====================================
        * delimiter <chars>                                         : CSV delimiter character (default: ,)
        * enclosure <chars>                                         : CSV enclosure character (default: ")
        * escape_char <char>                                        : CSV escape character to escape <enclosure> (default: \)
        * escape_string|escape on|off                               : Whether to escape string "\n" and "\r" as CRLF for string column (default: off)
        * unescape_string|unescape                                  : Whether to unescape string "\n" and "\r" as CRLF for string column (default: on)
        * skip_rows|skiprows|skip <number>                          : Number of rows to skip if CSV rows is not started from the first row (default: 0)
        
        
        Timestamp format options:
        =============================
        * format :  Transform the blow 3 formats from Oracle format to Java format when values,if set as 'java' then no transformation will be taken.
                    When format is 'oracle'(default), the formats will be replaced into Java format:
                        * YYYY or yyyy or yy => yyyy or yy
                        * MON or mon         => MMMM
                        * MM or mm           => MM
                        * DD or dd           => dd
                        * HH or hh           => hh
                        * HH24 or hh24       => HH
                        * MI or mi           => mm
                        * SS or ss           => ss
                        * .ff or xff or xff3 => .SSS
                        * .ff5 or xff6       => .SSSSS
                        * TZH:TZM or tzh:tzm => XXX
                        * TZR or tzr         => XXX
                    You should set this option as 'java' firstly if you want to directly specify the Java formats.
        * date_format|dateformat|date <format>                      : Date format string (default: auto)
        * timestamp_format|timestampformat|timestamp <format>       : Timestamp format string (default: auto)
        * timestamptz_format|timestamptzformat|timestamptz <format> : Timestamp with timezone format string (default: auto)
        * locale <locale>                                           : Locale used to parse date/timestamp (default: "")
    ]]

function this:parse_options(src_file,options)
    local typ,file=os.exists(src_file)
    if not typ then
        if not src_file:sub(1,128):find('[\\/]') then
            file=env.join_path(env._CACHE_BASE,src_file)
        else
            file=env.resolve_file(src_file)
        end
    end
    --env.checkerr(typ=="file","Target file %s does not exist.",src_file)
    local function next_token(pattern,lower)
        if options:sub(1,1)=='"' then
            --a quoted token is taken verbatim: trim() used to eat `delimiter " "` down to nothing
            local ed=options:find('"',2,true)
            env.checkerr(ed,"Unrecognized options: "..options)
            local piece=options:sub(2,ed-1)
            options=options:sub(ed+1):trim()
            return lower~=false and piece:lower() or piece,piece
        end
        local st,ed=options:find('^'..(pattern or '%S+'))
        if not st then return nil end
        local piece=options:sub(st,ed)
        options=options:sub(ed+1):trim()
        return lower~=false and piece:lower() or piece,piece
    end

    local cfg={TARGET_FILE=file}
    --keepcase: enumerated values are normalised to upper case, everything else (a charset, a
    --locale tag, a delimiter, the JSON null literal) travels verbatim
    local function push(opt,value,keepcase)
        if type(value)=="string" and not keepcase then value=value:upper() end
        cfg[opt:upper()]=value
    end

    local names={
        file_format={"csv","sql","json"},
        show={"off","all","ddl","dml"},
        create={"off","on"},
        truncate={"off","on"},
        errors={100},
        bad_file={"auto"},
        batch_rows={2048},
        has_header={"on","off"},
        row_limit={0},
        skip_rows={0},
        skip_columns={"auto"},
        scan_rows={200},
        report_mb={8},
        strict_mode={"off","on"},
        variable_format={"?",":"},
        json_row_type={"object","array"},
        json_keep_nulls={"on","off"},
        json_null_value={"null"},
        platform={"auto","oracle","mysql","pgsql","sqlserver","db2",'mssql','postgresql'},
        delimiter={","},
        enclosure={'"'},
        escape_char={[[\]]},
        escape_string={"off","on"},
        unescape_string={"on","off"},
        column_size={"auto","actual","maximum"},
        format={"oracle","java","mysql","pgsql","sqlserver","db2",'mssql','postgresql'},
        date_format={"auto"},
        timestamp_format={"auto"},
        timestamptz_format={"auto"},
        map_column_names={},
        encoding={"auto"}
    }

    --v[1] is the default, v[2] what a bare option falls back to, v.name the cfg key it writes
    local function add_option(n,v)
        names[n]=v
        v.name=v.name or n
        if #v>1 and not v.maps then
            local maps={}
            for i=1,#v do maps[v[i]:upper()]=true end
            v.maps=maps
        end
    end

    for n,v in pairs(names) do
        add_option(n,v)
        push(n,v[1],v.maps==nil)
    end

    push("platform",env.set.get("platform"))
    local ext=file:match("%.([^%.\\/]*)$")
    if ext then
        ext=ext:lower()
        if names.file_format.maps[ext:upper()] then push('FILE_FORMAT',ext) end
    end

    for n,v in pairs{
        type=names.file_format,
        file_type=names.file_format,
        new=names.create,
        show_ddl={"ddl","ddl",name="show"},
        show_dml={"dml","dml",name="show"},
        ddl={"ddl","ddl",name="show"},
        dml={"dml","dml",name="show"},
        strict=names.strict_mode,
        badfile=names.bad_file,
        jsonrowtype=names.json_row_type,
        json_type=names.json_row_type,
        jsonkeepnulls=names.json_keep_nulls,
        jsonnullvalue=names.json_null_value,
        bad=names.bad_file,
        skip=names.skip_rows,
        skiprows=names.skip_rows,
        skipcols=names.skip_columns,
        rowlimit=names.row_limit,
        limit=names.row_limit,
        header=names.has_header,
        scan=names.scan_rows,
        scanrows=names.scan_rows,
        date=names.date_format,
        dateformat=names.date_format,
        timestamp=names.timestamp_format,
        timestampformat=names.timestamp_format,
        timestamptz=names.timestamptz_format,
        timestamptzformat=names.timestamptz_format,
        mapcolumnnames=names.map_column_names,
        mapnames=names.map_column_names,
        batchrows=names.batch_rows,
        report=names.report_mb,
        var=names.variable_format,
        escape=names.escape_string,
        unescape=names.unescape_string,
        locale={""}
    } do
        add_option(n,v)
    end

    if self.init_options then
        self.init_options(cfg)
    end

    if options and options:trim()~="" then
        options=options:trim()
        local opt,org=next_token()
        env.checkhelp(opt=='set' and true or nil)
        while true do
            opt,org=next_token()
            local name,value,low=(org or ""):match("^([^= ]+)%s*=%s*(.*)$")
            if name then
                value=value:trim()
                opt,low=name:lower(),value:lower()
            end
            ::parse_opt::
            if not opt then break end
            local val=names[opt]
            env.checkerr(val,"Unrecognized option: "..opt:upper())
            if val.name=="map_column_names" then
                local maps
                if value then maps=value:match("^%b()$") else maps=next_token("%b()",false) end
                env.checkerr(maps,"Invalid option \""..opt:upper().."\" value: "..(value or "nil"))
                local list={}
                for csv_col,table_col in maps:sub(2,-2):gmatch("%s*([^=, ]+)%s*=%s*([^, ]+)") do
                    list[#list+1]=csv_col:upper()..'='..table_col:trim()
                end
                env.checkerr(#list>0,"Invalid option \""..opt:upper().."\" value: "..maps)
                push(val.name,table.concat(list,','),true)
            elseif val.name=="skip_columns" then
                --a parenthesised list, or the bare words auto/off
                local cols
                if value then
                    cols=value
                else
                    cols=next_token("%b()") or next_token()
                end
                local list=cols and cols:match("^%b()$")
                env.checkerr(list or cols=="off" or cols=="auto","Invalid option \""..opt:upper().."\" value: "..(cols or "nil"))
                push(val.name,cols)
            elseif val.name=='bad_file' then
                local fmt=value or next_token(nil,false)
                env.checkerr(fmt and not names[fmt:lower()],"Invalid option \""..opt:upper().."\" value: "..(fmt or "nil"))
                if fmt:lower()~='auto' then
                    fmt=env.join_path(fmt)
                    if not fmt:find('[\\/]') then
                        fmt=env.join_path(env._CACHE_BASE,fmt)
                    end
                end
                push(val.name,fmt,true)
            elseif val.name=="date_format" or val.name=="timestamp_format" or val.name=="timestamptz_format" then
                local fmt=value or next_token(nil,false)
                env.checkerr(fmt and not names[fmt:lower()],"Invalid option \""..opt:upper().."\" value: "..(fmt or "nil"))
                if cfg.FORMAT~='JAVA' then
                    fmt=fmt:lower()
                    fmt=fmt:gsub('%.(S+)',function(s) return '.'..s:upper() end)
                    fmt=fmt:gsub('([%.x]ff)(%d*)',function(s,d) return '.'..('S'):rep(tonumber(d) or 3) end)
                    for i=1,#ORA2JAVA do
                        fmt=fmt:gsub(ORA2JAVA[i][1],ORA2JAVA[i][2])
                    end
                    fmt=fmt:gsub('z$','Z'):gsub('(x+)$',function(s) return '.'..s:upper() end)
                end
                push(val.name,fmt,true)
            elseif type(val[1])=="number" then
                local num=low or next_token()
                env.checkerr(num and tonumber(num),"Invalid option \""..opt:upper().."\" value: "..(num or "nil"))
                push(val.name,tonumber(num))
            else
                --raw keeps the user's spelling, option is the lowercased form used for lookups
                local raw=value or next_token(nil,false) or ""
                local option=raw:lower()
                if val.maps and val.maps[option:upper()] then
                    push(val.name,option)
                elseif option~="" and not names[option] then
                    --neither a listed value nor another option name, so it is a free-form value
                    env.checkerr(not val.maps,"Invalid option \""..opt:upper().."\" value: "..option)
                    push(val.name,raw,true)
                else
                    push(val.name,val[2] or val[1],val.maps==nil)
                    if option=="" then break end
                    --low/value belong to the token just consumed; carrying them into the next
                    --round made `set create=new` re-read the same value forever
                    opt,value,low=option,nil,nil
                    goto parse_opt
                end
            end
        end
        env.checkerr(options=="","Unrecognized remaining options: "..options:upper())
    end

    return cfg,typ
end

function this:load(target_table,src_file,options)
    env.checkhelp(src_file)
    local cfg,typ=self:parse_options(src_file,options)
    env.checkerr(typ=="file","Target file %s does not exist.",src_file)
    local db=env.getdb()
    if db:is_connect() and db.check_obj then
        --check_obj raises DBC-00631 unless it is told to bypass, and with create=on the target is
        --supposed to be missing, so the lookup always bypasses and the check happens here instead
        local obj=db:check_obj(target_table,1)
        --a dry run prints the DDL and DML for a table that need not exist yet either
        local optional=cfg.CREATE~='OFF' or cfg.SHOW~='OFF'
        env.checkerr((obj and obj.object_name) or optional,"Cannot find target object: "..tostring(target_table))
        if obj and obj.object_name then
            target_table=obj.object_fullname or obj.object_name
            cfg.TARGET_TABLE=obj.target_table
            cfg.object_owner,cfg.object_name=obj.object_owner,obj.object_name
        end
    end

    print("Parameters:")
    print("===========")
    print(table.dump(cfg))

    if self.validate_options then
        self.validate_options(cfg)
    end

    env.checkerr(cfg.SHOW~='OFF' or env.set.get("readonly")=="off",'Operation not allowed in readonly mode.')
    local importer=db_loader.new(db.conn,cfg)
    local proxy=java.proxy({
        call=function(...)
            importer:importCSVData(target_table,cfg.TARGET_FILE)
        end
    },"org.dbcli.EventCallback")
    loader:doCall(importer,proxy)
end

function this:unload(target_file,query,options)
    env.checkhelp(query)
    local cfg=self:parse_options(target_file,options)
    local db=env.getdb()
    db:assert_connect()
    local rs
    if type(query)=="userdata" then
        rs=query
    else
        local typ,file=os.exists(query)
        if typ=='file' then
            local f=io.open(file,'r')
            env.checkerr(f,"Cannot read %s.",query)
            query=f:read("*a")
            f:close()
        end
        query=env.COMMAND_SEPS.match(query)
        local sql_type=db.get_command_type(query)
        env.checkerr(sql_type=="SELECT" or sql_type=="WITH","Unload query must be a SELECT statement.")
        rs=db:internal_call(query)
    end
    env.checkerr(type(rs)=="userdata" and rs.isClosed and not rs:isClosed(),tostring(rs).." must be an opened resultset.")
    print("Parameters:")
    print("===========")
    print(table.dump(cfg))

    local exporter=db_unloader.new(cfg)
    local proxy=java.proxy({
        call=function(...)
            exporter:exportToFile(rs,cfg.TARGET_FILE)
        end
    },"org.dbcli.EventCallback")
    loader:doCall(exporter,proxy)
end

function this:__onload()
    --overridable: mysql, pgsql and db2 each claim LOAD as a pass-through to the server, and
    --oracle/loader.lua re-binds both commands to its own instance
    env.set_command(self,self.load_command,self.load_helps,self.load,true,4,nil,true)
    env.set_command(self,self.unload_command,self.unload_helps,self.unload,true,4,nil,true)
end

return this.new()
