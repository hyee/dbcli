local env, pairs, ipairs = env, pairs, ipairs
local math, table, string, class, event = env.math, env.table, env.string, env.class, env.event
local type,tostring,tonumber=type,tostring,tonumber
local clear=table.clear
local grid = class()
local console = console
local getWidth = console.getBufferWidth
local getScreenWidth=console.getScreenWidth
local reps=string.rep
local params = {
    [{'HEADSEP', 'HEADDEL'}] = {name = "title_del", default = '-', desc = "The delimiter to devide header and body when printing a grid"},
    [{'COLSEP', 'COLDEL'}] = {name = "col_del", default = ' ', desc = "The delimiter to split the fields when printing a grid"},
    [{'ROWSEP', 'ROWDEL'}] = {name = "row_del", default = '', desc = "The delimiter to split the rows when printing a grid"},
    COLWRAP = {name = "col_wrap", default = 0, desc = "If the column size is larger than COLDEL, then wrap the text", range = "0 - 32767"},
    COLAUTOSIZE = {name = "col_auto_size", default = 'auto', desc = "Define the base of calculating column width", range = "auto,head,body,trim"},
    COLSIZE = {name="col_size",default=4096,desc="Max column size of a result set",range='5-32767'},
    ROWNUM = {name = "row_num", default = "off", desc = "To indicate if need to show the row numbers", range = "on,off"},
    HEADSTYLE = {name = "title_style", default = "none", desc = "Display style of the grid title", range = "upper,lower,initcap,none"},
    PIVOT = {name = "pivot", default = 0, desc = "Pivot a grid when next print, afterward the value would be reset", range = "-30 - +30"},
    PIVOTSORT = {name = "pivotsort", default = "on", desc = "To indicate if to sort the titles when pivot option is on", range = "on,off,head,*"},
    MAXCOLS = {name = "maxcol", default = 1024, desc = "Define the max columns to be displayed in the grid", range = "4-1024"},
    [{'SCALE','DIGITS'}] = {name = "digits", default = 38, desc = "Define the digits for a number", range = "0 - 38"},
    SEP4K = {name = "sep4k", default = "off", desc = "Define whether to show number with thousands separator", range = "on,off"},
    [{"HEADING","HEAD"}] = {name = "heading", default = "on", desc = "Controls printing of column headings in reports", range = "on,off"},
    [{"LINESIZE","LINES"}]= {name = "linesize", default = 0, desc = "Define the max chars in one line, other overflow parts would be cutted.", range = '0-32767'},
    [{'AUTOHIDE','BYPASSEMPTYRS'}] = {name = "autohide", default = "off", desc = "Controls whether to hide empty row/column. on-row/col-column/all-both", range = "on,off,col,all"},
    PIPEQUERY = {name = "pipequery", default = "off", desc = "Controls whether to print each row one-by-one of a resultset", range = "on,off"},
--NULL={name="null_value",default="",desc="Define display value for NULL."}
}

local function toNum(v)
    if type(v) == "number" then
        return v
    elseif type(v) == "string" then
        return tonumber((v:gsub(",", '')))
    else
        return tonumber(v)
    end
end

function grid.set_param(name, value)
    if (name == "TITLEDEL" or name == "ROWDEL") and #value > 1 then
        return print("The value should be only one char!")
    elseif name == "COLWRAP" and value > 0 and value < 30 then
        return print("The value cannot be less than 30 !")
    elseif name=='AUTOHIDE' then
        --print(value,debug.traceback())
    end
    grid[grid.params[name].name] = value
    return value
end

function grid.format_title(v)
    if grid.title_style == "none" then
        return v
    end
    return v[grid.title_style](v)
end

local linesize
function grid.cut(row, format_func, format_str, is_head)
    local byte_len,print_len
    if type(row) == "table" then
        local colbase = row.col_auto_size or grid.col_auto_size
        local cs = grid.colsize
        if cs then
            if colbase ~= 'auto' and colbase ~= 'trim' then
                for i, _ in ipairs(cs) do
                    byte_len,print_len,row[i] = tostring(row[i]):ulen(cs[i][1])
                end
            end
            if is_head then
                local nor = env.ansi.get_color("NOR")
                for i, _ in ipairs(cs) do
                    if type(row[i]) == "string" and row[i]:trim() == "" then
                        row[i] = nor .. row[i]
                    end
                end
            end
        end
        row = format_func(format_str, table.unpack(row))
    end
    print_len = type(format_func) == "number" and format_func or linesize
    if #row > print_len then
        byte_len,print_len,row=row:ulen(print_len)
    end
    return row .. env.ansi.get_color('NOR')
end

local s_format = "%s%%s%s"
function grid.fmt(format, ...)
    local idx, v, lpad, rpad, pad = 0, nil
    local args = {...}
    local fmt = format:gsub("(%%(-?)(%d*)s)",
        function(g, flag, siz)
            idx = idx + 1
            if siz == "" then return g end
            v = args[idx]
            if not v or type(v) ~= "string" then return g end
            siz=tonumber(siz)
            lpad, rpad, pad = "", "", ""
            local l1,l2=tostring(v):ulen()
            if l1~=l2 or siz>99 then
                pad = reps(" ", siz-l2)
                if flag ~= "-" and siz<99 then
                    lpad = pad
                else
                    rpad = pad
                end
                return s_format:format(lpad, rpad)
            end
            return g
        end)
    return fmt:format(...)
end

function grid.sort(rows, cols, bypass_head)
    local head
    local sorts = {}
    local has_header
    if rows.__class then rows, has_header = rows.data, rows.include_head end
    if type(rows[1])~='table' then return rows end
    local titles=rows[1]._org or rows[1]
    for ind in tostring(cols):gsub('^,*(.-),*$', '%1'):gmatch("([^,]+)") do
        local col, l
        if tonumber(ind) then
            ind = tonumber(ind)
            col = math.abs(ind)
            l = ind
        elseif type(ind) == "string" and (bypass_head == true or has_header) then
            if ind:sub(1, 1) == '-' then
                col = ind:sub(2)
                l = -1
            else
                col = ind
                l = 1
            end
            for k, v in ipairs(titles) do
                if col:upper() == tostring(v):upper() then
                    col = k
                    break
                end
            end
            if type(col) ~= "number" then
                return rows
            end
        else
            return rows
        end
        sorts[#sorts + 1] = function() return col, l end
    end
    
    if bypass_head or has_header then
        head={table.remove(rows, 1)}
        while has_header and type(rows[1])=='table' and rows[1][0]==0 do head[#head+1]=table.remove(rows, 1) end
    end
    
    table.sort(rows, function(a, b)
        for _, item in ipairs(sorts) do
            local col, l = item()
            local a1, b1 = a._org and a._org[col] or a[col], b._org and b._org[col] or b[col]
            if a1 == nil then
                return false
            elseif b1 == nil then
                return true
            else
                local a2, b2 = toNum(a1), toNum(b1)
                if a2 and b2 then
                    a1, b1 = a2, b2
                else
                    a1, b1 = tostring(a1), tostring(b1)
                end
            end
            
            if type(a1) == "string" then
                a1, b1 = a1:strip_ansi():upper(), b1:strip_ansi():upper()
            end
            
            if a1 ~= b1 then
                if l < 0 then return a1 > b1 end
                return a1 < b1
            end
        end
        return false
    end)
    
    if head then
        for i=#head,1,-1 do 
            table.insert(rows, 1, head[i])
        end
    end
    return rows
end

function grid.line_wrap(text,width)
    width=math.max(1,width-30)
    local len,result,pos,pos1,c,p=#text,{},1
    local pt="|)]}, ="
    local usize,csize,l1,l2=0,0
    local function size(line)
        l1, l2 = line:ulen()
        usize=usize<l1 and l1 or usize
        csize=csize<l2 and l2 or csize
        return line
    end

    local lines={}
    while true do
        result[#result+1]=text:sub(pos,pos+width-1)
        pos=pos+width
        pos1=pos
        local ln=0
        while true do
            pos1=pos1+1
            c=p or text:sub(pos1,pos1)
            p=text:sub(pos1+1,pos1+1)
            if c=='' or (pt:find(c,1,true) and (p=='' or not pt:find(p,1,true))) then
                ln=ln+1
                result[#result+1]=text:sub(pos,pos1)
                lines[#lines+1]=size(table.concat(result,''))
                clear(result)
                pos=pos1+1
                break
            end
        end
        if len<pos then break end
    end
    return lines,usize,csize
end

-- Display pivot view of grid data
-- @param rows table Grid data to display
-- @param col_del string Column delimiter (optional)
-- @param pivotsort string Pivot sort mode (optional)
-- @return table Pivot display data
function grid.show_pivot(rows, col_del, pivotsort)
    local keys = {}
    -- if not title then print(table.dump(rows)) end
    local vert_count = rows and rows.verticals and math.min(#rows, rows.verticals + 1)
    rows = rows.data or rows
    local colinfo = rows.colinfo or rows[1] and rows[1].colinfo or {}
    local title = rows[1]
    local max_col_size = grid.col_size
    local pivot = math.abs(grid.pivot) + 1
    local sep = grid.title_del
    sep = (sep == "-" and "=") or (sep == "=" and "||") or (sep == "." and ":") or sep
    sep = ' ' .. sep .. ' '
    -- if not grid.col_del:match("^[ \t]+$") then sep = "" end
    if pivot > #rows then pivot = #rows end
    if pivot > 2 then sep = '' end
    local max_len = 0
    local byte_len, print_len, new_val
    local top_rows = {{}}
    local _, value
    local max_col_count = 12
    local null_val = env.set.NULL and env.set.get('NULL') or ''
    local auto_hide = grid.autohide
    if #rows < 2 and (auto_hide == 'on' or auto_hide == 'all') then return {} end

    local wrap_width = grid.col_wrap
    local line_size = grid.linesize
    if line_size <= 10 then line_size = math.max(60, getScreenWidth(console) - (#env.space) * 2) end
    if max_col_size >= 1024 and wrap_width == 0 then
        wrap_width = line_size
    end

    -- Get formatted value for a cell
    local function get_value(title, row_idx, col_idx)
        if not colinfo[col_idx] then colinfo[col_idx] = {column_name = title} end
        _, value = grid.format_column(true, type(title) == "table" and title or colinfo[col_idx], tonumber(rows[row_idx][col_idx]) or rows[row_idx][col_idx], row_idx - 1)
        byte_len, print_len, new_val = tostring(value or null_val):trim():ulen(max_col_size)
        if wrap_width > 0 and print_len > wrap_width and not new_val:sub(1, 1024):find('\n', 1, true) then
            value, byte_len, print_len = grid.line_wrap(new_val, wrap_width)
            new_val = table.concat(value, '\n')
        end
        max_col_count = max_col_count < print_len and print_len or max_col_count
        return new_val
    end

    -- Build column keys and calculate max length
    for k, v in ipairs(title) do
        keys[v] = k
        byte_len, print_len, new_val = v:ulen(max_col_size)
        max_len = max_len < print_len and print_len or max_len
        if vert_count then
            for i = 1, math.min(30, vert_count - 1) do
                if not top_rows[i] then top_rows[i] = {} end
                top_rows[i][k] = get_value(v, i + 1, k)
            end
        end
    end

    local color = env.ansi.get_color
    local nor, hor = color("NOR"), color("HEADCOLOR")

    local result = {}
    -- Handle vertical display mode
    if vert_count and vert_count > 1 then
        max_len = max_len + 3
        local width = console:getScreenWidth() - max_len - 2 - #env.space * 2
        local col_name = 'Column Value'
        result[1] = {'|', "#", '|', 'Column Name', col_name}
        local size
        local titles = {}
        for k, t in ipairs(title) do
            byte_len, print_len, new_val = grid.format_title(t):rtrim():ulen(max_col_size)
            titles[k] = ("%s %-" .. (max_len + byte_len - print_len) .. "s%s %s"):format(hor, new_val, nor, '=')
        end
        local seq_size = #tostring(vert_count) + 3
        local rows_per_group = math.min(vert_count - 1, math.floor(1.0 * (width + seq_size) / (max_col_count + seq_size)))
        for j = 2, rows_per_group do
            size = #result[1]
            result[1][size + 1], result[1][size + 2], result[1][size + 3], result[1][size + 4] = "|", "#", '|', col_name
        end

        local row
        local start_idx, end_idx
        local empty_counts = {}
        for i = 1, vert_count - 1 do
            if rows_per_group < 2 or math.fmod(i, rows_per_group) == 1 then start_idx, end_idx = #result, #result + #titles end
            for j, v in ipairs(titles) do
                local idx = start_idx + j
                new_val = top_rows[i] and top_rows[i][j] or get_value(t, i + 1, j)
                empty_counts[idx] = (empty_counts[idx] or 0) + (new_val ~= '' and new_val ~= null_val and 1 or 0)
                if not result[idx] then
                    result[idx] = {'|', i, '|', v, new_val}
                else
                    size = #result[idx]
                    result[idx][size + 1], result[idx][size + 2], result[idx][size + 3], result[idx][size + 4] = '|', i, '|', ' ' .. new_val
                end
            end
            if rows_per_group < 2 or i == vert_count - 1 or math.fmod(i, rows_per_group) == 0 then
                if auto_hide == 'col' or auto_hide == 'all' then
                    for j = end_idx, start_idx + 1, -1 do
                        if empty_counts[j] == 0 then table.remove(result, j) end
                    end
                end
                result[#result + 1] = {'$HIY$-$NOR$'}
            end
        end
        return result
    end

    -- Handle normal pivot mode
    local pivot_sort = (pivotsort or grid.pivotsort):lower()
    if pivot_sort == "on" then table.sort(title) end
    local head_col = pivot_sort == 'head' and tostring(title[1]):lower() or (pivot_sort ~= 'on' and pivot_sort ~= 'off') and pivot_sort or nil
    local _, value
    for k, v in ipairs(title) do
        byte_len, print_len, new_val = v:ulen(max_col_size)
        local row = {("%s%-" .. (max_len + byte_len - print_len) .. "s %s%s"):format(hor, grid.format_title(new_val) .. (v:lower() == head_col and ' =>' or ''), nor, sep)}

        for i = 2, pivot, 1 do
            row[#row + 1] = get_value(v, i, keys[v])
        end

        local should_print = not colinfo[keys[v]] or not colinfo[keys[v]].no_print
        if pivot == 2 and row[#row] == '' and (auto_hide == 'col' or auto_hide == 'all') then
            should_print = false
        end
        if v:lower() == head_col then
            table.insert(result, 1, row)
        elseif should_print then
            table.insert(result, row)
        end
    end

    -- Handle pivot == 2 with positive grid.pivot
    if pivot == 2 and grid.pivot > 0 then
        for i = 1, #result, 2 do
            if result[i + 1] then
                local k, v = '* ' .. result[i + 1][1], result[i + 1][2]
                if type(v) == "string" then
                    v:gsub('[%s\r\n\t]+$', ''):gsub('\r?\n', function() k = k .. '\n.' end)
                end
                table.insert(result[i], k)
                table.insert(result[i], v)
            else
                table.insert(result[i], "")
                table.insert(result[i], "")
            end
        end

        for i = 1024, 0, -2 do
            if result[i] then table.remove(result, i) end
        end
        grid.pivot = 1
    elseif grid.pivot > 0 and #result > 0 and head_col == nil then
        local titles = {" "}
        for i = 2, #result[1], 1 do
            titles[i] = ' #' .. (i - 1)
        end
        table.insert(result, 1, titles)
    end
    result.pivot = grid.pivot
    return result
end

function grid:ctor(include_head)
    if include_head == nil then
        include_head = (grid.heading or "on") == "on" and true or false
        self.headind = include_head == false and -1 or 0
    else
        self.headind = include_head == false and 1 or 0
    end
    self.include_head = self.headind == 0 and true or false
    self.colsize = table.new(255, 0)
    self.data = table.new(1000, 0)
end

local max_integer = math.pow(2, 46)
local java_cast=java.cast
local String=String
local string_format=String.format


function grid.format_column(include_head, colinfo, value, rownum,instance,rowind,row)
    if include_head then
        local result = event.callback("ON_COLUMN_VALUE", {colinfo.column_name, value, rownum,instance,rowind,row})
        value,colinfo.is_number,colinfo.no_print=result[2],colinfo.is_number or result.is_number,colinfo.no_print or result.no_print
    end
    
    if rownum > 0 and (type(value) == "number" or include_head and colinfo.is_number) then
        if value == nil then return true, '' end
        local v1, v2 = tonumber(type(value)=='string' and (value:gsub(',','')) or value)
        local is_same=type(value)=='number' or tostring(v1)==value
        if not v1 then return true,value end
        local pre, scal = math.modf(v1)
        if grid.sep4k == "on" then
            if v1 ~= pre then
                local scale=grid.digits<38 and grid.digits or 2
                v1 = math.round(v1, scale)
                v2 = string.format_number("%,."..scale.."f", value, 'double')
            else
                v2 = string.format_number("%,.0f", value, 'double')
            end
        elseif grid.digits < 38 and scal > 0 then
            if not is_same then
                v2= value:gsub('(%.'..reps('%d',grid.digits)..').*','%1')
            else
                v2 = math.round(v1, grid.digits)
            end
        elseif not is_same then
            v1=value
        end
        value = v2 or v1
        if tostring(value):find('e', 1, true) then return true, string.format('%99.38f', value):gsub(' ', ''):gsub('%.?0+$', '') end
        return true, value
    end
    return false, value == nil and '' or value
end

local printables={
    ['\0']='',
    ['\1']='\\1',
    ['\2']='\\2',
    ['\3']='\\3',
    ['\4']='\\4',
    ['\5']='\\5',
    ['\6']='\\6',
    ['\7']='\\7',
    ['\8']='\\8',
    ['\9']='    ',
    ['\10']='\10',
    ['\11']='\\11',
    ['\12']='\\12',
    ['\13']='\\13',
    ['\14']='\\14',
    ['\15']='\\15',
    ['\16']='\\16',
    ['\17']='\\17',
    ['\18']='\\18',
    ['\19']='\\19',
    ['\20']='\\20',
    ['\21']='\\21',
    ['\22']='\\22',
    ['\23']='\\23',
    ['\24']='\\24',
    ['\25']='\\25',
    ['\26']='\\26',
    ['\27']='\27',
    ['\28']='\\28',
    ['\29']='\\29',
    ['\30']='\\30',
    ['\31']='\\31'
}
local empty={}
-- Add a row to the grid and process column information
-- @param row table Row data to add
-- @return table result The updated grid data
function grid:add(row)
    if type(row) ~= "table" then return end
    local row_data = {_org = {}}
    local result, header_idx, colsize = self.data, self.headind, self.colsize
    local title_style = grid.title_style
    local col_size_base = self.col_auto_size or grid.col_auto_size
    local auto_hide = self.autohide or self.bypassemptyrs or grid.autohide
    local row_num = grid.row_num
    local null_val = env.set.NULL and env.set.get('NULL') or ''
    local max_col_size = grid.col_size
    grid.colsize = self.colsize
    for k, v in pairs(row) do row_data[k] = v end
    -- Handle first row initialization
    if self.headind == -1 then
        self.headind = 1
        return
    end
    -- Add row number if enabled
    if row_num == "on" then
        table.insert(row_data, 1, header_idx == 0 and "#" or header_idx)
    end
    -- Initialize break groups and handle header column info
    if not self.break_groups then self.break_groups = {} end
    if header_idx == 0 then
        if row_num == "on" and row_data.colinfo then table.insert(row_data.colinfo, 1, {is_number = true}) end
        self.colinfo = row_data.colinfo
    end

    local line_count = 1
    row_data[0] = header_idx

    local col_count = #result > 0 and #result[1] or #row_data
    local row_size, byte_len, print_len = 0
    -- Run statement pattern for splitting lines
    local split_pattern = '[' .. (header_idx == 0 and '' or ' ') .. '\a\r\f\b\v]*\n[\a\r\f\b\v]*'
    -- Helper function to strip length based on autohide settings
    local function strip_len(str)
        if auto_hide == 'all' or auto_hide == 'col' then
            local len = #(str:ltrim())
            if len == 0 or str == null_val then return 0, '' end
        end
        return #str, str
    end
    -- Process each column in the row
    for col_idx = 1, col_count do
        local val = row_data[col_idx]
        if type(val) == 'userdata' then val = tostring(val) end
        row_data._org[col_idx] = val
        if col_idx > grid.maxcol then break end
        local col_width, unicode_size, formatted_val, is_number = 0, 0, val
        local start_pos, end_pos
        -- Initialize column size info if not exists
        if not colsize[col_idx] then colsize[col_idx] = {0, 1} end

        -- Initialize column info if not exists
        if not self.colinfo then self.colinfo = {} end
        if not self.colinfo[col_idx] then
            local info = {column_name = #result > 0 and result[1]._org[col_idx] or tostring(val), numbers = 0}
            self.colinfo[col_idx] = info
            self.colinfo[info.column_name:upper()] = col_idx
        elseif self.colinfo[col_idx].is_number and type(val) == 'string' then
            val, start_pos, end_pos = val:from_ansi()
        end

        -- Format column value
        is_number, formatted_val = grid.format_column(self.include_head, self.colinfo[col_idx], val, #result, self, header_idx, row_data)

        if tostring(val) ~= tostring(formatted_val) then val = formatted_val end
        if start_pos or end_pos then val = (start_pos or '') .. val .. (end_pos or '') end
        -- Handle column separator pattern
        if colsize[col_idx][3] and type(val) == 'string' and colsize[col_idx][3]:find(val, 1, true) then
            col_width, colsize[col_idx][3] = strip_len(colsize[col_idx][3])
        -- Handle numeric values in body
        elseif is_number and header_idx > 0 then
            byte_len, col_width = 0, strip_len(tostring(val))
            if col_width > 0 then
                byte_len, col_width = tostring(val):ulen()
            else
                val = ''
            end
            colsize[col_idx][3], colsize[col_idx][4] = nil
            self.colinfo[col_idx].numbers = (self.colinfo[col_idx].numbers or 0) + 1
        -- Handle null values and empty strings
        elseif type(val) ~= "string" or val == "" or (val == null_val) then
            val = tostring(val)
            col_width = strip_len(val)
            self.colinfo[col_idx].nulls = (self.colinfo[col_idx].nulls or 0) + 1
        -- Handle string values
        else
            if header_idx > 0 then self.colinfo[col_idx].chars = (self.colinfo[col_idx].chars or 0) + 1 end
            local line_parts = empty
            val = val:convert_ansi()
            -- Handle header row
            if header_idx == 0 then
                val, byte_len = val:gsub('[\n\r]+', ''):gsub("([^|]+)%c*|%c*([^|]+)", function(a, b)
                        local len1, len2, len3, len4
                        len1, len2, a = a:ulen(math.min(99, max_col_size))
                        len3, len4, b = b:ulen(math.min(99, max_col_size))
                        local max_len = math.max(len2, len4)
                        unicode_size = math.max(len1, len3)
                        col_width = max_len
                        line_parts[1] = reps(' ', math.floor((max_len - len2) / 2)) .. a .. reps(' ', math.ceil((max_len - len2) / 2))
                        line_parts[2] = reps(' ', math.floor((max_len - len4) / 2)) .. b .. reps(' ', math.ceil((max_len - len4) / 2))
                        return table.concat(line_parts, '\n')
                end, 1)
                local val1 = val:strip_ansi()
                -- Detect separator pattern in header
                if #val1 <= 3 and val1:find('^%W+$') and val1 ~= '#' and val1 ~= '%' then
                    colsize[col_idx][3] = val
                elseif val == "" then
                    colsize[col_idx][3] = ""
                end
                -- Apply title style if enabled
                if title_style ~= "none" and self.include_head then
                    val = grid.format_title(val)
                end
            -- Handle body rows
            else
                val = val:sub(1, 1048576 * 4):rtrim()
                for part in val:gsplit(split_pattern) do
                    part = part:gsub('%c', printables)
                    -- Deal with unicode chars
                    byte_len, print_len, part = part:ulen(max_col_size)
                    line_parts[#line_parts + 1] = part
                    unicode_size = unicode_size < byte_len and byte_len or unicode_size
                    if print_len == 0 and part ~= '' then print_len = 1 end
                    col_width = col_width < print_len and print_len or col_width
                end

                -- Handle separator pattern in body
                if colsize[col_idx][3] and val ~= colsize[col_idx][3] and val ~= "" then
                    if col_idx == 1 then
                        local val1 = val:strip_ansi()
                        if not val1:match('^%W$') then
                            colsize[col_idx][3] = nil
                        else
                            row_size = 1
                        end
                    else
                        colsize[col_idx][3] = nil
                    end
                end

                -- Handle line wrapping
                if #line_parts == 1 then
                    val = line_parts[1]
                    local col_wrap = grid.col_wrap
                    if col_count == 1 and max_col_size >= 1024 and header_idx < 2 then
                        local linesize = self.linesize
                        if linesize <= 10 then linesize = getWidth(console) - (#env.space) * 2 end
                        if unicode_size > math.max(linesize, max_col_size) then
                            col_wrap = col_wrap == 0 and linesize or col_wrap
                        end
                    end
                    if col_wrap > 0 and unicode_size > col_wrap then
                        line_parts, unicode_size, col_width = grid.line_wrap(val, col_wrap)
                        empty = {}
                    end
                end
            end

            -- Update line count based on parts
            if line_count < #line_parts then line_count = #line_parts end
            -- Consolidate line parts
            if not line_parts[1] then
                unicode_size, col_width, val = val:ulen(math.min(max_col_size, header_idx == 0 and 99 or max_col_size))
            elseif #line_parts > 1 then
                val, empty = line_parts, {}
            else
                val = line_parts[1]
                clear(empty)
            end

            -- Ensure minimum column width
            if col_width == 0 and val ~= '' then col_width = 1 end

            -- Set alignment flag
            if self.colinfo[col_idx].is_number then
                colsize[col_idx][2] = 1
            elseif header_idx > 0 then
                colsize[col_idx][2] = -1
            end
        end

        row_data[col_idx] = val

        -- Handle column width based on pivot and col_size_base
        if grid.pivot == 0 and header_idx == 0 and (col_size_base == "body" or col_size_base == "trim") and self.include_head then
            colsize[col_idx][1] = 0
            colsize[col_idx].__trimsize = (col_size_base == "trim" and col_width) or 0
        elseif colsize[col_idx][1] < col_width and not (self.include_head and grid.pivot == 0 and header_idx ~= 0 and col_size_base == 'head') then
            if colsize[col_idx].__trimsize and colsize[col_idx][1] == 0 then
                if val ~= null_val then
                    col_width = math.max(col_width, colsize[col_idx].__trimsize)
                else
                    col_width = colsize[col_idx][1]
                end
            end
            colsize[col_idx][1] = col_width
        end
        -- Store original column size
        colsize[col_idx].org_size = math.max(colsize[col_idx].org_size or 0, col_width)
        -- Handle autohide for columns
        if auto_hide == 'col' or auto_hide == 'all' then
            if header_idx == 0 then
                colsize[col_idx].head_size, colsize[col_idx][1] = colsize[col_idx][1], 0
                col_width = 0
            elseif colsize[col_idx][1] > 0 and colsize[col_idx].head_size then
                col_width = math.max(colsize[col_idx][1], colsize[col_idx].head_size)
                colsize[col_idx][1], colsize[col_idx].head_size = col_width
            end
        end
        -- Update row size based on column width
        row_size = not colsize[col_idx][3] and row_size < col_width and col_width or row_size
    end

    local temp_row
    local function add_row(r)
        result[#result + 1] = r
        temp_row = r
    end

    row_data.rsize = row_size
    if row_size > 0 or auto_hide == 'off' or header_idx == 0 then
        if line_count == 1 then
            add_row(row_data)
        else
            for i = 1, line_count, 1 do
                local r = table.new(#row_data, 3)
                r[0], r._org = row_data[0], row_data._org
                for col_idx = 1, col_count do
                    local val = row_data[col_idx]
                    if type(val) ~= "table" then
                        row_data[col_idx] = table.new(line_count, 0)
                        row_data[col_idx][1] = val
                        val = row_data[col_idx]
                    end
                    local size = line_count - #val
                    for j = 1, size do
                        if header_idx == 0 then
                            local orig = val[1]
                            if #orig > 0 and orig == colsize[col_idx][3] then
                                if (col_idx == 1 or row_data[col_idx - 1][size - j + 1]:trim() == '') and (type(row_data[col_idx + 1]) ~= 'table' or row_data[col_idx + 1][size - j + 1]:trim() == '') then
                                    table.insert(val, 1, '')
                                else
                                    table.insert(val, 1, colsize[col_idx][3] or '')
                                end
                            else
                                table.insert(val, 1, colsize[col_idx][3] or '')
                            end
                        else
                            val[#val + 1] = ""
                        end
                    end
                    r[col_idx] = val[i] == nil and "" or val[i]
                end
                r.rsize = row_size
                add_row(r)
            end
            row_data = temp_row
        end
    end

    -- Update header index
    self.headind = header_idx + (row_size == 0 and auto_hide ~= 'off' and header_idx > 0 and 0 or 1)
    -- Handle break groups separator
    local sep = self.break_groups.__SEP__
    if header_idx > 1 and sep ~= nil then
        local row = {}
        for col_idx, col_info in ipairs(self.colinfo) do
            if self.break_groups[col_info.column_name:upper()] then
                row[col_idx] = sep
                -- if row_data[col_idx] == '' then
                --     row_data[col_idx] = self.break_groups[col_info.column_name:upper()]
                -- end
            end
        end
        self.break_groups.__SEP__ = nil
        result = self:add(row)
        row = table.remove(result)
        row.sep = sep
        table.insert(result, #result, row)
    end

    return result
end

function grid:add_calc_ratio(column, adjust, name,scale)
    adjust = tonumber(adjust) or 1
    if not self.ratio_cols then self.ratio_cols = {} end
    if type(column) == "string" then
        if not self.include_head then return end
        local head = self.data[1]
        if not head then return end
        for k, v in pairs(head) do
            if tostring(v):upper() == column:upper() then
                self.ratio_cols[k] = {adjust,name or "<-Ratio",scale or 2}
            end
        end
    elseif type(column) == "number" then
        self.ratio_cols[column] = {adjust,name or "<-Ratio",scale or 2}
    end
end

-- Format grid data into displayable table
-- @param col_del string Column delimiter (optional, defaults to grid.col_del)
-- @param row_del string Row delimiter (optional, defaults to grid.row_del)
-- @return table screen_rows Formatted row data
-- @return table output Output table containing raw formatted data
function grid:wellform(col_del, row_del)
    self.break_groups = nil
    local result, colinfo, colsize = self.data, self.colinfo, self.colsize
    if #result == 0 or (grid.autohide == 'on' or grid.autohide == 'all') and result[#result][0] == 0 then
        return {}, {}
    end
    local rownum = grid.row_num
    local col_width, screen_rows, output = #result, table.new(#result + 1, 0), table.new(#result + 1, #result[1])
    if col_width == 0 then return screen_rows end
    local row_format = ""
    local title_seps, row_sep_line = {}, ""
    col_del = col_del or grid.col_del
    row_del = (row_del or grid.row_del):sub(1, 1)
    local pivot = grid.pivot
    local indx = rownum == "on" and 1 or 0
    row_format = col_del:ltrim()
    local format_func = grid.fmt
    grid.colsize = self.colsize
    -- Calculate ratio columns: if ratio columns are configured, calculate percentages and insert into data
    if type(self.ratio_cols) == "table" and grid.pivot == 0 then
        local keys = {}
        for k, v in pairs(self.ratio_cols) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        local data_rows = self.data

        for c = #keys, 1, -1 do
            local sum, idx = 0, keys[c]
            local adjustment, name, scale = table.unpack(self.ratio_cols[idx])
            for _, row in ipairs(data_rows) do
                sum = sum + (toNum(row._org[idx]) or 0)
            end
            for i, row in ipairs(data_rows) do
                local ratio_value = " "
                if row[0] == 0 and i == 1 then
                    ratio_value = name
                elseif sum > 0 then
                    ratio_value = toNum(row._org[idx])
                    if ratio_value ~= nil then
                        ratio_value = string.format("%." .. scale .. "f%%", math.round(100 * ratio_value / sum * adjustment, scale))
                    else
                        ratio_value = " "
                    end
                end
                table.insert(row, idx + 1, ratio_value)
            end
            table.insert(colsize, idx + 1, {7, 1})
            table.insert(colinfo, idx + 1, {column_name = name, is_number = true})
        end
        self.ratio_cols = nil
    end

    -- Generate row format string
    local color = env.ansi.get_color
    local nor, hor, hl = color("NOR"), color("HEADCOLOR"), color("GREPCOLOR")
    local header_format, max_col_width = row_format, 0
    local col_separators = {}
    local prev_col, next_col, prev_sep_idx, prev_none_zero_idx, sep = {}, nil, -1, -1
    local cols = #colsize
    -- Helper function to calculate column separator
    local function calc_col_sep(sep, row_sep)
        return row_sep:find('[~#=%-%*%+]') and sep:gsub('[|:]', '+'):gsub('[\\/]', row_sep) or sep
    end

    row_sep_line = calc_col_sep(row_format, row_del)
    local trim_count = 0
    -- Process each column to build format strings
    for col_idx, col_info in ipairs(colsize) do
        -- Set number alignment flag
        if col_info[2] == 1 or (not colinfo[col_idx].is_number and (colinfo[col_idx].chars or 0) == 0 and (colinfo[col_idx].numbers or 0) > 0) then
            colinfo[col_idx].is_number = true
            col_info[2] = 1
        end
        -- Clear separator info for columns after first when max width is 0
        if max_col_width == 0 and col_idx > 1 then col_info[3] = nil end
        -- Get column width and separator
        col_width, col_separators[col_idx] = col_info[1], col_info[3]
        -- Handle separator columns
        if col_separators[col_idx] then
            if prev_none_zero_idx <= prev_sep_idx and col_idx > 1 then
                col_width = 0
                col_info[3] = nil
            end
            prev_sep_idx = col_idx
        elseif col_width > 0 then
            prev_none_zero_idx = col_idx
        end
        col_info[1] = col_width
        -- Get next column and determine separator
        next_col = colsize[col_idx + 1] or {}
        sep = (col_separators[col_idx] or next_col[3] or next_col[1] == 0) and "" or " "

        -- Handle beginning zero width columns: if previous column has separator or is first column, set separator to empty string
        if col_width == 0 and (prev_col[3] or col_idx - trim_count == 1) then
            if col_idx - trim_count == 1 then
                trim_count = trim_count + 1
            end
            sep = ''
        end
        -- Apply column delimiter based on pivot settings
        if (sep ~= "" and pivot == 0) or (pivot ~= 0 and col_idx ~= 1 + indx and (pivot ~= 1 or col_idx ~= 3 + indx)) then
            sep = col_del
        end

        -- Remove trailing separator for last column
        if col_idx == cols then sep = sep:rtrim() end

        -- Build format string for zero width and normal width columns
        if col_width == 0 then
            row_format = row_format .. "%s" .. (col_idx == cols and nor or '') .. sep
            header_format = header_format .. "%s" .. sep
            col_separators[col_idx] = ''
        else
            row_format = row_format .. "%" .. (col_width * col_info[2]) .. "s" .. (col_idx == cols and nor or '') .. sep
            header_format = header_format .. (col_info[3] and '' or hor) .. "%" .. (col_width * col_info[2]) .. "s" .. nor .. sep
        end

        -- Check if column has any non-empty values in header
        local is_empty = true
        for i = 1, #result do
            if result[i][0] == 0 and type(result[i][col_idx]) == "string" and result[i][col_idx]:trim() ~= "" then
                is_empty = false
            end

            if (result[i][0] or 1) > 0 then
                break
            end
        end
        -- Build title separator for column
        title_seps[col_idx] = (col_info[3] and calc_col_sep(col_info[3], grid.title_del)) or reps(not is_empty and grid.title_del or " ", col_width)

        -- Build row separator line
        if row_del ~= "" then
            row_sep_line = row_sep_line .. row_del:rep(col_width) .. calc_col_sep(sep, row_del)
        end
        prev_col = col_info
        max_col_width = max_col_width < col_width and col_width or max_col_width
    end
    -- Clean up trailing separators
    if prev_none_zero_idx <= prev_sep_idx and prev_sep_idx < #colsize then
        for k, v in pairs(col_separators) do
            if k >= prev_none_zero_idx and #v > 0 then
                col_separators[k], title_seps[k] = '', ''
            end
        end
    end

    -- Handle max column width = 0: if autohide is off or col only, restore original column widths
    if max_col_width == 0 then
        if grid.autohide == 'off' or grid.autohide == 'col' then
            for k, v in ipairs(colsize) do
                v[1] = v.org_size
                max_col_width = max_col_width + v[1]
            end
        end
        if max_col_width > 0 then
            return self:wellform(col_del, row_del)
        else
            return {}, {}
        end
    end

    -- Calculate line size based on console width
    linesize = self.linesize

    if linesize <= 10 then linesize = getWidth(console) end
    linesize = linesize - #env.space - 1

    local trim_line = self.cut
    -- Add row separator line at the beginning if row_del is set
    if row_del ~= "" then
        output[#output + 1] = row_sep_line:gsub("%s", row_del)
        screen_rows[#screen_rows + 1] = trim_line(output[#output])
    end

    -- Remove leading/trailing delimiters in merge mode
    if grid._merge_mode and col_del ~= ' ' and #col_del > 0 then
        header_format = header_format:sub(2, -2)
        row_format = row_format:sub(2, -2)
    end

    local row_count = #result
    -- Process each row in the result
    for k, v in ipairs(result) do
        local should_include, match_count = 1, 0
        -- Ensure row has enough columns
        while #v < #colsize do v[#v + 1] = '' end
        local row_sep
        -- Detect separator row
        if v.sep then
            row_sep = v.sep
        elseif v[0] ~= 0 and v.rsize == 1 and type(v[1]) == 'string' then
            local v1 = v[1]:strip_ansi()
            local v2 = tostring(v[2] or ''):strip_ansi()
            local v3 = tostring(v[3] or ''):strip_ansi()
            if v1:find('[~#|=@_:<>&/\\%$%-%+%*%.]') and
               (v2 == '' or v2 == v1 or v2:find('^%W+$')) and
               (v3 == '' or v3 == v1 or v3:find('^%W+$') or v[3] == col_separators[3])
            then
                row_sep = v1
            end
        end

        -- Apply column separators to row
        for sep_idx, sep_val in pairs(col_separators) do
            if not (sep_idx == 1 and row_sep) then
                if v[0] > 0 or not(v[sep_idx] == '' and (v[sep_idx + 1] or '') == '' and (sep_idx == 1 or v[sep_idx - 1] == '')) then
                    v[sep_idx] = row_sep or sep_val
                end
            end
        end
        -- Adjust title style (center)
        local separator_format
        if v[0] == 0 then
            -- Center align header values
            for col, value in ipairs(v) do
                local pad = colsize[col][1] - #value
                if pad >= 2 then
                    if colsize[col][1] <= 40 or pad == 2 then
                        v[col] = v[col]:cpad(colsize[col][1])
                    elseif colsize[col][1] <= 60 then
                        v[col] = ' ' .. v[col]
                    end
                end
            end
        elseif row_sep then
            -- Format separator row
            separator_format = calc_col_sep(row_format, row_sep)
            local sep_char = row_sep
            for sep_idx, sep_val in ipairs(title_seps) do
                v[sep_idx] = sep_val:sub(1, 1) == grid.title_del and sep_val:gsub('.', sep_char) or sep_val
            end
            -- Remove duplicate separator line
            if output[#output] == row_sep_line then
                output[#output], screen_rows[#screen_rows] = nil
            end
        end

        -- Set format function and format string for row
        v.format_func, v.fmt = format_func, v[0] == 0 and header_format or separator_format or row_format
        local row = trim_line(v, v.format_func, v.fmt, v[0] == 0)

        -- Apply highlighting for header row
        if v[0] == 0 then
            row = row .. nor
        -- Apply grep highlighting for body rows
        elseif env.printer.grep_text then
            row, match_count = row:gsub(env.printer.grep_text, hl .. "%0" .. nor)
            if (match_count == 0 and not env.printer.grep_dir) or (match_count > 0 and env.printer.grep_dir) then should_include = 0 end
        end

        output[#output + 1] = v

        -- Add row to formatted rows if it should be included
        if should_include == 1 then
            screen_rows[#screen_rows + 1] = row
        end

        -- Add separator lines between different row types
        if not result[k + 1] or result[k + 1][0] ~= v[0] then
            if not row_sep and #row_del == 1 and should_include == 1 and v[0] ~= 0 then
                row_sep_line = row_sep_line:gsub('%s', row_del)
                screen_rows[#screen_rows + 1] = trim_line(row_sep_line)
                output[#output + 1] = row_sep_line
            elseif v[0] == 0 then
                -- Add title separator line after header
                output[#output + 1] = format_func(calc_col_sep(row_format, grid.title_del), table.unpack(title_seps))
                screen_rows[#screen_rows + 1] = trim_line(output[#output])
            end
        end
    end

    -- Add title separator line in non-merge mode
    if not grid._merge_mode and result[#result][0] > 0 and (row_del or "") == "" and (col_del or ""):trim() ~= "" then
        local line = trim_line(title_seps, format_func, row_format)
        line = line:gsub(" ", grid.title_del):gsub(col_del:trim(), function(a) return ('+'):rep(#a) end)
        screen_rows[#screen_rows + 1] = line
        output[#output + 1] = line
        table.insert(screen_rows, 1, line)
        table.insert(output, 1, line)
    end
    -- Set metadata on output
    output.len = row_count
    output.colinfo, (type(output[1]) == 'table' and output[1] or {}).colinfo = colinfo, colinfo

    return screen_rows, output
end

function grid.format(rows, include_head, col_del, row_del)
    local this
    if rows.__class then
        this = rows
    else
        this = grid.new(include_head)
        for i, rs in ipairs(rows) do this:add(rs) end
    end
    return this:wellform(col_del, row_del)
end

function grid.get_config(sql)
    local all, grid_cfg = sql:match("(grid%s*[=:]%s*(%b{}))")
    if grid_cfg then
        sql = sql:replace(all, '', true):gsub('/%*%s*%*/', '')
        grid_cfg = table.totable(grid_cfg)
    else
        grid_cfg = {}
    end
    return sql, grid_cfg
end

function grid.tostring(rows, include_head, col_del, row_del, rows_limit, pivot,pivotsort)
    if pivot then grid.pivot = pivot end
    if rows.verticals or (grid.pivot ~= 0 and include_head ~= false) then
        rows = grid.show_pivot(rows,nil,pivotsort)
        if math.abs(grid.pivot) == 1 then
            include_head = false
        else
            rows_limit = rows_limit and rows_limit + 2
        end
    end
    local output
    rows,output = grid.format(rows, include_head, col_del, row_del)
    rows_limit = rows_limit and math.min(rows_limit, #rows) or #rows
    env.set.force_set("pivot", 0)
    if not pivotsort then 
        env.set.force_set("PIVOTSORT", env.set._p['PIVOTSORT'] or 'on') 
    end
    return table.concat(rows, "\n", 1, rows_limit),output
end

function grid.format_output(output,rows_limit,include_head)
    if type(output)=="table" then
        rows_limit=rows_limit and math.min(rows_limit,#output) or #output
        for i=1,rows_limit do
            local v=output[i]
            if type(v)=='table' then
                local s=v.format_func(v.fmt,table.unpack(v))
                env.event.callback("ON_PRINT_GRID_ROW",v,{i,rows_limit},v.format_func,v.fmt,include_head)
                output[i]=s
            end
        end
        output=table.concat(output,'\n',1,rows_limit)
    end
    return output
end

function grid.print(rows, include_head, col_del, row_del, rows_limit, prefix, suffix)
    rows_limit = rows_limit or 10000
    local str = prefix and (prefix .. "\n") or ""
    local test, size
    if include_head == 'test' then test, include_head = true, nil end
    
    if rows.__class then
        include_head = rows.include_head
        size = #rows.data
    else
        include_head = grid.new(include_head).include_head
        size = #rows + (include_head and 1 or 0)
    end
    local data,output=grid.tostring(rows, include_head, col_del, row_del, rows_limit)
    if not data or data=='' then return end
    str = str .. data
    if test then env.write_cache("grid_output.txt", str) end
    if type(output)=="table" then
        for k,v in ipairs(output) do
            env.event.callback("ON_PRINT_GRID_ROW",v,{k,#output},v.format_func,v.fmt,include_head)
        end
    end
    env.printer.print_grid(str)
    if suffix then print(suffix) end
end

-- Merge multiple grid tables and print to terminal
-- @param tabs table Array of grid tables to merge
-- @param is_print boolean|string Whether to print to terminal ('plain' for plain text)
-- @param prefix string Prefix to add before output (optional)
-- @param suffix string Suffix to add after output (optional)
-- @return table|string Formatted string or table data
function grid.merge(tabs, is_print, prefix, suffix)
    -- Helper function to get string display width
    local function strip(str)
        local byte_len, print_len = str:ulen()
        return print_len
    end
    local footer_pat = env.ansi.mask('UDL', '(.-)', 'NOR'):gsub('%[', '%%[')
    -- Redraw table with specified dimensions
    local function redraw(tab, cols, rows)
        local new_tab = {_is_drawed = true, topic = tab.topic or tab.title, footprint = tab.footprint or tab.bottom}
        local function push(line) new_tab[#new_tab + 1] = line end
        local actual_cols = strip(tab[#tab])
        local h_fill = '|' .. space.rep(' ', cols - 2) .. '|'
        local max_row_cnt = (tab.max_rows and tab.max_rows + 2 or rows) + 2
        if tab._is_drawed then
            local col_space = cols - actual_cols
            local push_row = function(row)
                if col_space == 0 then
                    push(row)
                elseif col_space > 0 then
                    local right = col_space
                    local last = row:sub(-1)
                    push(row:sub(1, -2) .. reps(last == '+' and '-' or ' ', right) .. last)
                else
                    push(grid.cut(row, cols))
                end
            end
            for row_idx, row in ipairs(tab) do
                if row_idx == #tab then
                    local line = row:gsub(footer_pat, function(c) return reps(' ', #c) end)
                    line = line:gsub('.', function(c) return c == '+' and '|' or c == '-' and ' ' or c end)
                    for i = row_idx + 1, rows do
                        push_row(line)
                    end
                elseif row_idx >= rows and tab.height == 0 and tab.min_height < rows then
                    push_row('+' .. reps('-', actual_cols - 2) .. '+')
                    break
                end
                push_row(row)
            end
        else
            local col_diff = cols - actual_cols - 2
            local col_space = reps(' ', col_diff)
            local format = '+%s+'
            local header = format:format(reps('-', cols - 2))
            local convert = env.ansi.convert_ansi
            if (tab.topic or "") ~= "" then
                local topic, st, ed = tab.topic:from_ansi()
                push(format:format(topic:match('[^\n]+'):cpad(cols - 2, '-',
                    function(left, str, right)
                        return convert(("%s$PROMPTCOLOR$%s$NOR$%s"):format(left, grid.cut(topic, cols - 2):to_ansi(st, ed), right))
                    end)))
            else
                push(header)
            end
            format = '|%s%s|'
            for row_idx, row in ipairs(tab) do
                push(format:format(col_diff >= 0 and row or grid.cut(row, cols - 2), col_space))
                if #new_tab >= math.min(rows, max_row_cnt) - 1 then break end
            end
            for i = #new_tab + 1, rows - 1 do
                push(h_fill)
            end
            if (tab.footprint or "") ~= "" then
                local footer, st, ed = tab.footprint:from_ansi()
                footer = footer:match('[^\n]+'):cpad(cols - 2, '-',
                function(left, str, right)
                    return convert(("%s$UDL$%s$NOR$%s"):format(left or '', (grid.cut(footer, cols - 2)):to_ansi(st, ed), right or ''))
                end)
                push('+' .. footer .. '+')
            else
                push(header)
            end
        end

        return new_tab
    end

    local frame_list = {}
    local print_size = env.set and env.set.get('PRINTSIZE') or 512
    local function _merge(tabs, is_wrap)
        local newtab = {}
        local maxwidth = 0
        local function push(line)
            newtab[#newtab + 1] = line
            maxwidth = math.max(maxwidth, strip(line))
        end

        local result = {}
        -- Process each tab in the list
        for i = 1, #tabs do
            local tab, sep, nexttab = tabs[i]
            if type(tab) == "table" and #tab > 0 then
                local seq = i + 1
                while true do
                    sep, nexttab = tabs[seq], tabs[seq + 1]
                    if type(sep) ~= "string" or type(nexttab) ~= "string" then break end
                    seq = seq + 1
                end
                if type(sep) == "string" and type(nexttab) == "table" and #nexttab > 0 then
                    newtab = {_is_drawed = true}
                    local m1, m2 = tab._is_drawed and 2 or 0, nexttab._is_drawed and 2 or 0
                    local width1, width2 = (tab.width and (tab.width + 2) or (strip(tab[#tab]) - m1)) + 2, (nexttab.width and (nexttab.width + 2) or (strip(nexttab[#nexttab]) - m2)) + 2
                    local height1, height2 = (tab.height and (tab.height + 2) or (#tab - m1)) + 2, (nexttab.height and (nexttab.height + 2) or (#nexttab - m2)) + 2
                    height1, height2 = math.min(tab.max_rows and (tab.max_rows + 4) or 1e5, height1), math.min(nexttab.max_rows and (nexttab.max_rows + 4) or 1e5, height2)
                    if sep == '|' then
                        local maxlen = math.max(height1, height2)
                        newtab.adj_height=maxlen
                        tab, nexttab = redraw(tab, width1, maxlen), redraw(nexttab, width2, maxlen)
                        local fmt = '%s  %s'
                        for rowidx = 1, math.max(#tab, #nexttab) do
                            push(fmt:format(tab[rowidx], nexttab[rowidx]))
                        end
                    elseif sep == '+' then
                        local maxlen = math.max(height1, height2)
                        newtab.adj_height=maxlen
                        tab, nexttab = redraw(tab, width1, maxlen), redraw(nexttab, width2, maxlen)
                        local fmt = '%s%s%s'
                        for rowidx = 1, maxlen do
                            push(fmt:format(tab[rowidx]:sub(1, -2), (rowidx == 1 or rowidx == maxlen) and '+' or '|', nexttab[rowidx]:sub(2)))
                        end
                    else --sep=='-'
                        if (nexttab.height or 1)<=0 then
                            newtab.height=0
                            height2=printsize
                        end
                        local maxlen = math.max(width1, width2)
                        tab, nexttab = redraw(tab, maxlen, height1), redraw(nexttab, maxlen, height2)
                        if newtab.height==0 then
                            newtab.min_height=#tab
                        end
                        newtab.adj_width=maxlen
                        for _, row in ipairs(tab) do push(row) end
                        --push(reps(' ',maxlen))
                        for _, row in ipairs(nexttab) do push(row) end
                    end
                    newtab.calc_height,newtab.calc_width=#newtab,#newtab[1]
                    tabs[seq + 1] = newtab
                    i = seq
                else
                    tab._is_drawed = tab._is_drawed and true or false
                    if is_wrap then
                        local m = tab._is_drawed and 2 or 0
                        local width = (tab.width or (strip(tab[#tab]) - m)) + 2
                        local height = (tab.height or (#tab - m)) + 2
                        height = math.min(tab.max_rows and tab.max_rows + 4 or 1e5, height)
                        maxwidth = math.max(maxwidth, strip(tab[#tab]))
                        tab = redraw(tab, width, height)
                    end
                    result[#result + 1] = tab
                end
            end
        end
        if #result == 1 then return result[1] end
        newtab = {_is_drawed = true}
        for i = 1, #result do
            if i > 1 then
                push(reps(' ', maxwidth))
            end
            if not result[i]._is_drawed then newtab._is_drawed = false end
            for _, row in ipairs(result[i]) do
                local spaces = maxwidth - strip(row)
                local s = spaces <= 0 and '' or reps(' ', spaces)
                push(row .. s)
            end
        end
        return newtab
    end

    local color = env.ansi.get_color
    local nor, hor, hl = color("NOR"), color("HEADCOLOR"), color("GREPCOLOR")
    -- Format nested tables recursively
    local function format_tables(tabs, is_wrap)
        local auto_hide = grid.autohide
        local result = {}
        local max_idx = 30
        for idx = 0, max_idx do
            local tab = tabs[idx]
            if type(tab) == "table" then
                if tab._is_drawed ~= nil then
                    result[#result + 1] = tab
                else
                    local found = false
                    for sub_idx = 0, max_idx do
                        local child_tab = tab[sub_idx]
                        if type(child_tab) == "table" and (type(child_tab.data) == "table" or type(child_tab[#child_tab]) == "table") then
                            found = true
                            break
                        end
                    end

                    -- Check if table needs recursive formatting
                    if found then
                        result[#result + 1] = format_tables(tab, false)
                    else
                        -- Format table with grid.tostring
                        local topic, footer, width, height, max_rows = tab.topic, tab.footprint, tab.width, tab.height, tab.max_rows
                        local bypass1, bypass2, auto_size1, auto_size2 = grid.autohide, tab.autohide or tab.bypassemptyrs, grid.col_auto_size, tab.autosize
                        -- Apply temporary autohide and autosize settings
                        if auto_size2 then grid.col_auto_size = auto_size2 end
                        bypass2 = bypass2 == true and 'on' or bypass2 == false and 'off' or bypass2 or bypass1
                        grid.autohide = bypass2
                        grid._merge_mode = true
                        local _, output = grid.tostring(tab, true, tab.colsep, "", nil, tab.pivot, tab.pivotsort)
                        grid._merge_mode = nil
                        -- Restore original settings
                        if auto_size2 then grid.col_auto_size = auto_size1 end
                        grid.autohide = bypass1
                        tab = {}
                        -- Process output rows and apply grep filtering
                        for k, row in ipairs(output) do
                            local should_include, match_cnt = 1, 0
                            if type(row) == "table" then
                                local is_body_row = not row[0] or row[0] > 0
                                row = row.format_func(row.fmt, table.unpack(row))
                                -- Apply grep highlighting to body rows
                                if is_body_row and env.printer.grep_text then
                                    row, match_cnt = row:gsub(env.printer.grep_text, hl .. "%0" .. nor)
                                    if (match_cnt == 0 and not env.printer.grep_dir) or (match_cnt > 0 and env.printer.grep_dir) then
                                        should_include = 0
                                    end
                                end
                            end
                            if should_include == 1 then tab[#tab + 1] = row end
                        end

                        -- Restore table properties
                        tab.topic, tab.footprint, tab.width, tab.height, tab.max_rows = topic, footer, width, height, max_rows
                        if #tab > 0 then
                            result[#result + 1] = tab
                        end
                    end
                end
            elseif tab then
                result[#result + 1] = tab
            end
        end
        grid.autohide = auto_hide
        return _merge(result, is_wrap)
    end

    local result = format_tables(tabs, true)

    -- Print to terminal or return formatted string
    if is_print == true or is_print == 'plain' then
        local output_tab = {}
        local display_height = tabs.max_rows or #result + 1
        local space = env.printer.top_mode == true and env.space or ''
        -- Add prefix
        if prefix then
            output_tab[1] = space .. prefix:convert_ansi()
            env.event.callback("ON_PRINT_GRID_ROW", output_tab[1])
        end
        -- Process each row
        for row_idx, row in ipairs(result) do
            output_tab[#output_tab + 1] = space .. grid.cut(row, linesize):convert_ansi()
            env.event.callback("ON_PRINT_GRID_ROW", row, {row_idx, #result})
            if #output_tab >= display_height - 1 then
                if row_idx < #result then
                    output_tab[#output_tab + 1] = space .. grid.cut(result[#result], linesize)
                    env.event.callback("ON_PRINT_GRID_ROW", output_tab[#output_tab], {row_idx, #result})
                end
                break
            end
        end
        -- Display in top mode
        if env.printer.top_mode == true then
            output_tab[#output_tab + 1] = ' '
            local height = console:getScreenHeight()
            for i = #output_tab, height, -1 do
                table.remove(output_tab, i)
            end
            return console:display(output_tab)
        end

        -- Build output string
        local output_str = table.concat(output_tab, "\n")
        if is_print == true then
            env.printer.print_grid(output_str)
            if suffix then print(suffix) end
            return
        end
        return output_str, table.concat(result, '\n')
    else
        return result
    end
end

function grid.onload()
    local set = env.set.init
    grid.params = {}
    for k, v in pairs(params) do
        grid[v.name] = v.default
        if type(k) == "table" then
            for _, k1 in ipairs(k) do grid.params[k1] = v end
        else
            grid.params[k] = v
        end
        set(k, grid[v.name], grid.set_param, "grid", v.desc, v.range)
    end
    env.ansi.define_color("HEADCOLOR", "BRED;HIW", "ansi.grid", "Define grid title's color, type 'ansi' for more available options")
end

grid.finalize='N/A'
return grid
