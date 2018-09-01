local env, pairs, ipairs = env, pairs, ipairs
local math, table, string, class, event = env.math, env.table, env.string, env.class, env.event
local grid = class()
local console = console
local getWidth = console.getBufferWidth

local params = {
    [{'HEADSEP', 'HEADDEL'}] = {name = "title_del", default = '-', desc = "The delimiter to devide header and body when printing a grid"},
    [{'COLSEP', 'COLDEL'}] = {name = "col_del", default = ' ', desc = "The delimiter to split the fields when printing a grid"},
    [{'ROWSEP', 'ROWDEL'}] = {name = "row_del", default = '', desc = "The delimiter to split the rows when printing a grid"},
    COLWRAP = {name = "col_wrap", default = 0, desc = "If the column size is larger than COLDEL, then wrap the text", range = "0 - 32767"},
    COLAUTOSIZE = {name = "col_auto_size", default = 'auto', desc = "Define the base of calculating column width", range = "head,body,auto"},
    ROWNUM = {name = "row_num", default = "off", desc = "To indicate if need to show the row numbers", range = "on,off"},
    HEADSTYLE = {name = "title_style", default = "none", desc = "Display style of the grid title", range = "upper,lower,initcap,none"},
    PIVOT = {name = "pivot", default = 0, desc = "Pivot a grid when next print, afterward the value would be reset", range = "-30 - +30"},
    PIVOTSORT = {name = "pivotsort", default = "on", desc = "To indicate if to sort the titles when pivot option is on", range = "on,off"},
    MAXCOLS = {name = "maxcol", default = 1024, desc = "Define the max columns to be displayed in the grid", range = "4-1024"},
    DIGITS = {name = "digits", default = 38, desc = "Define the digits for a number", range = "0 - 38"},
    SEP4K = {name = "sep4k", default = "off", desc = "Define whether to show number with thousands separator", range = "on,off"},
    HEADING = {name = "heading", default = "on", desc = "Controls printing of column headings in reports", range = "on,off"},
    LINESIZE = {name = "linesize", default = 0, desc = "Define the max chars in one line, other overflow parts would be cutted.", range = '0-32767'},
    BYPASSEMPTYRS = {name = "bypassemptyrs", default = "off", desc = "Controls whether to print an empty resultset", range = "on,off"},
    PIPEQUERY = {name = "pipequery", default = "off", desc = "Controls whether to print an empty resultset", range = "on,off"},
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
    end
    grid[grid.params[name].name] = value
    return value
end

function grid.format_title(v)
    if grid.title_style == "none" then
        return v
    end
    if not v[grid.title_style] then
        string.initcap = function(v1)
            return (' ' .. v1):lower():gsub("([^%w])(%w)", function(a, b) return a .. b:upper() end):sub(2)
        end
    end
    return v[grid.title_style](v)
end

local linesize
function grid.cut(row, format_func, format_str, is_head)
    if type(row) == "table" then
        local colbase = grid.col_auto_size
        local cs = grid.colsize
        if cs then
            if colbase ~= 'auto' then
                for i, _ in ipairs(cs) do
                    row[i] = tostring(row[i]):sub(1, cs[i][1])
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
    local siz = type(format_func) == "number" and format_func or linesize
    if #row > siz then
        local tab, len, count, clen, ulen = {}, -siz, 0
        for piece, pattern in row:gsplit("(\27%[[%d;]*[mK])") do
            clen, ulen = piece:ulen()
            len, count = len + ulen, count + 1
            tab[#tab + 1] = len < 0 and piece or piece:sub(1, ulen - len)
            if (pattern or "") ~= "" then tab[#tab + 1] = pattern end
            if len >= 0 then
                tab[#tab + 1] = env.ansi.get_color('NOR')
                break
            end
        end
        return table.concat(tab, '')
    end
    return row .. env.ansi.get_color('NOR')
end

local s_format = "%s%%%s%ss%s"
function grid.fmt(format, ...)
    local idx, v, lpad, rpad, pad = 0, nil
    local args = {...}
    local fmt = format:gsub("(%%(-?)(%d*)s)",
        function(g, flag, siz)
            idx = idx + 1
            if siz == "" then return g end
            siz = tonumber(siz)
            lpad, rpad, pad = "", "", ""
            v = args[idx]
            if not v or type(v) ~= "string" then return g end
            local v1 = v:strip_ansi()
            local _, length = v1:ulen()
            local strips = #v - #v1
            siz = siz + strips + (#v1 - length)
            if siz > 99 then
                pad = string.rep(" ", siz - length + strips) or ""
                if flag ~= "-" then
                    lpad = pad
                else
                    rpad = pad
                end
                siz = ''
            end
            return s_format:format(lpad, flag, tostring(siz), rpad)
        end)
    --print(fmt,...)
    return fmt:format(...)
end


function grid.sort(rows, cols, bypass_head)
    local head
    local sorts = {}
    local has_header
    if rows.__class then rows, has_header = rows.data, rows.include_head end
    for ind in tostring(cols):gsub('^,*(.-),*$', '%1'):gmatch("([^,]+)") do
        local col, l
        if tonumber(ind) then
            ind = tonumber(ind)
            col = math.abs(ind)
            l = ind
        elseif type(ind) == "string" and bypass_head == true then
            if ind:sub(1, 1) == '-' then
                col = ind:sub(2)
                l = -1
            else
                col = ind
                l = 1
            end
            for k, v in ipairs(rows[1]) do
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
    
    if bypass_head or has_header then head = table.remove(rows, 1) end
    
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
    
    if head then table.insert(rows, 1, head) end
    return rows
end

function grid.show_pivot(rows, col_del)
    local title = rows[1]
    local keys = {}
    
    local pivot = math.abs(grid.pivot) + 1
    local del = grid.title_del
    del = (del == "-" and "=") or (del == "=" and "||") or (del == "." and ":") or del
    del = ' ' .. del .. ' '
    --if not grid.col_del:match("^[ \t]+$") then del="" end
    if pivot > #rows then pivot = #rows end
    
    local maxlen = 0
    for k, v in ipairs(title) do
        keys[v] = k
        if maxlen < v:len() then
            maxlen = v:len()
        end
    end
    
    local r = {}
    local color = env.ansi.get_color
    local nor, hor = color("NOR"), color("HEADCOLOR")
    if grid.pivotsort == "on" then table.sort(title) end
    for k, v in ipairs(title) do
        table.insert(r, {("%s%-" .. maxlen .. "s %s%s "):format(hor, grid.format_title(v), nor, del)})
        for i = 2, pivot, 1 do
            local _, value = grid.format_column(true, type(v) == "table" and v or {column_name = v}, rows[i][keys[v]], i - 1)
            table.insert(r[k], tostring(value):trim())
        end
    end
    
    if pivot == 2 and grid.pivot > 0 then
        for i = 1, #r, 2 do
            if r[i + 1] then
                local k, v = '. ' .. r[i + 1][1], r[i + 1][2]
                if type(v) == "string" then
                    v:gsub('[%s\r\n\t]+$', ''):gsub('[\n\r]', function()k = k .. '\n.' end)
                end
                table.insert(r[i], k)
                table.insert(r[i], v)
            else
                table.insert(r[i], "")
                table.insert(r[i], "")
            end
        end
        
        for i = 1024, 0, -2 do
            if r[i] then table.remove(r, i) end
        end
        grid.pivot = 1
    elseif grid.pivot > 0 then
        local titles = {" "}
        for i = 2, #r[1], 1 do
            titles[i] = ' #' .. (i - 1)
        end
        table.insert(r, 1, titles)
    end
    r.pivot = grid.pivot
    return r
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

local max_integer = math.pow(2, 63)
function grid.format_column(include_head, colinfo, value, rownum,instance)
    if include_head then
        value = event.callback("ON_COLUMN_VALUE", {colinfo.column_name, value, rownum,instance})[2]
    end
    if value == nil then return false, '' end
    if rownum > 0 and (type(value) == "number" or include_head and colinfo.is_number) then
        local v1, v2 = tonumber(value)
        if v1 and v1 < max_integer or type(value) == "number" then
            local pre, scal = math.modf(v1)
            if grid.sep4k == "on" then
                if v1 ~= pre then
                    v2 = string.format_number("%,.2f", v1, 'double')
                else
                    v2 = string.format_number("%,d", v1, 'long')
                end
            elseif grid.digits < 38 and scal > 0 then
                v2 = math.round(v1, grid.digits)
            end
            value = v2 or v1
        end
        if tostring(value):find('e', 1, true) then return true, string.format('%99.38f', value):gsub(' ', ''):gsub('%.?0+$', '') end
        return true, value
    end
    return false, value
end

function grid:add(row)
    if type(row) ~= "table" then return end
    local rs = {_org = {}}
    local result, headind, colsize = self.data, self.headind, self.colsize
    local title_style = grid.title_style
    local colbase = grid.col_auto_size
    local rownum = grid.row_num
    grid.colsize = self.colsize
    for k, v in pairs(row) do rs[k] = v end
    if self.headind == -1 then
        self.headind = 1
        return
    end
    if rownum == "on" then
        table.insert(rs, 1, headind == 0 and "#" or headind)
    end
    
    if headind == 0 then
        if rownum == "on" and rs.colinfo then table.insert(rs.colinfo, 1, {is_number = true}) end
        self.colinfo = rs.colinfo
    end
    
    local lines = 1
    rs[0] = headind
    local cnt = 0
    local cols = #result > 0 and #result[1] or #rs
    
    --run statement
    for k = 1, cols do
        local v = rs[k]
        rs._org[k] = v
        if k > grid.maxcol then break end
        local csize, v1, is_number = 0, v
        if not colsize[k] then colsize[k] = {0, 1} end
        is_number, v1 = grid.format_column(self.include_head, self.colinfo and self.colinfo[k] and self.colinfo[k] or {column_name = #result > 0 and result[1]._org[k] or v}, v, #result,self)
        if tostring(v) ~= tostring(v1) then v = v1 end
        if is_number then
            csize = #tostring(v)
        elseif type(v) ~= "string" or v == "" then
            v = tostring(v) or ""
            csize = #v
        else
            if headind == 0 then
                v = v:gsub("([^|]+)|([^|]+)", function(a, b)
                    a, b = a:trim(' '), b:trim(' ')
                    local len1, len2 = a:len(), b:len()
                    local max_len = math.max(len1, len2)
                    return ('%s%s\n%s%s'):format(
                        string.rep(' ', math.ceil((max_len - len1) / 2)), a,
                        string.rep(' ', math.ceil((max_len - len2) / 2)), b)
                end)
                if v=='|' then 
                    colsize[k][3]='|'
                end
            elseif colsize[k][3] then
                v='|'
            end
            
            local col_wrap = grid.col_wrap
            if linesize and cols == 1 then col_wrap = math.min(col_wrap > 0 and col_wrap or linesize, linesize) end
            
            if col_wrap > 0 and not v:find("\n") and #v > col_wrap then
                local v1 = {}
                while v and v ~= "" do
                    table.insert(v1, v:sub(1, col_wrap))
                    v = v:sub(col_wrap + 1)
                end
                v = table.concat(v1, '\n')
            end
            local grp = {}
            v = v:convert_ansi():gsub('\192\128', ''):gsub('%z+', '')
            if headind > 0 then v = v:gsub("[%s ]+$", ""):gsub("[ \t]+[\n\r]", "\n"):gsub("\t", '    ') end
            
            --if the column value has multiple lines, then split lines into table
            for p in v:gmatch('([^\n\r]+)') do
                grp[#grp + 1] = p
                --deal with unicode chars
                local l, len = p:strip_ansi():ulen()
                if csize < len then csize = len end
            end
            if #grp > 1 then v = grp end
            if lines < #grp then lines = #grp end
            if headind > 0 then
                colsize[k][2] = -1
            end
        end
        
        
        if headind == 0 and title_style ~= "none" then
            v = grid.format_title(v)
        end
        rs[k] = v
        
        if grid.pivot == 0 and headind == 1 and colbase == "body" and self.include_head then colsize[k][1] = 1 end
        if (grid.pivot ~= 0 or colbase ~= "head" or not self.include_head or headind == 0)
            and colsize[k][1] < csize
        then
            colsize[k][1] = csize
        end
    end
    
    if lines == 1 then result[#result + 1] = rs
    else
        for i = 1, lines, 1 do
            local r = table.new(#rs, 2)
            r[0], r._org = rs[0], rs._org
            for k = 1, cols do
                local v = rs[k]
                if type(v) ~= "table" then
                    rs[k] = table.new(lines, 0)
                    rs[k][1] = v
                    v = rs[k]
                end
                local siz = lines - #v
                for j = 1, siz do
                    if headind == 0 then
                        table.insert(v, 1, colsize[k] or '')
                    else
                        v[#v + 1] = ""
                    end
                end
                r[k] = v[i] == nil and "" or v[i]
            end
            result[#result + 1] = r
        end
    end
    self.headind = headind + 1
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
        self.ratio_cols[column] = adjust
    end
end

function grid:wellform(col_del, row_del)
    local result, colsize = self.data, self.colsize
    local rownum = grid.row_num
    local siz, rows = #result, table.new(#self.data + 1, 0)
    if siz == 0 then return rows end
    local fmt = ""
    local title_dels, row_dels = {}, ""
    col_del = col_del or grid.col_del
    row_del = (row_del or grid.row_del):sub(1, 1)
    local pivot = grid.pivot
    local indx = rownum == "on" and 1 or 0
    fmt = col_del:gsub("^%s+", "")
    row_dels = fmt
    local format_func = grid.fmt
    grid.colsize = self.colsize
    
    if type(self.ratio_cols) == "table" and grid.pivot == 0 then
        local keys = {}
        for k, v in pairs(self.ratio_cols) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        local rows = self.data
        
        for c = #keys, 1, -1 do
            local sum, idx = 0, keys[c]
            local adj,name,scale=table.unpack(self.ratio_cols[idx])
            for _, row in ipairs(rows) do
                sum = sum + (toNum(row._org[idx]) or 0)
            end
            for i, row in ipairs(rows) do
                local n = " "
                if row[0] == 0 and i == 1 then
                    n = name
                elseif sum > 0 then
                    n = toNum(row._org[idx])
                    if n ~= nil then
                        n = string.format("%."..scale.."f%%", math.round(100 * n / sum * adj ,scale))
                    else
                        n = " "
                    end
                end
                table.insert(row, idx + 1, n)
            --print(table.dump(row))
            end
            table.insert(colsize, idx + 1, {7, 1})
        end
        self.ratio_cols = nil
    end
    
    --Generate row formatter
    local color = env.ansi.get_color
    local nor, hor, hl = color("NOR"), color("HEADCOLOR"), color("GREPCOLOR")
    local head_fmt = fmt
    
    for k, v in ipairs(colsize) do
        siz = v[1]
        local del = (v[3] or (colsize[k+1] or {})[3]) and "" or " "
        if (del~="" and pivot == 0) or (pivot ~= 0 and k ~= 1 + indx and (pivot ~= 1 or k ~= 3 + indx)) then 
            del = col_del
        end
        if k == #colsize then del = del:gsub("%s+$", "") end
        if siz == 0 then
            fmt = fmt .. "%s"
            head_fmt = head_fmt .. "%s"
        else
            fmt = fmt .. "%" .. (siz * v[2]) .. "s" .. del
            head_fmt = head_fmt .. (v[3] and '' or hor) .. "%" .. (siz * v[2]) .. "s" .. nor .. del
        end
        
        local is_empty = true
        for i = 1, #result do
            if result[i][0] == 0 and type(result[i][k]) == "string" and result[i][k]:trim() ~= "" then
                is_empty = false
            end
            
            if (result[i][0] or 1) > 0 then
                break
            end
        end
        table.insert(title_dels, v[3] or string.rep(not is_empty and grid.title_del or " ", siz))
        
        if row_del ~= "" then
            row_dels = row_dels .. row_del:rep(siz) .. del
        end
    end
    
    linesize = self.linesize
    if linesize <= 10 then linesize = getWidth(console) end
    linesize = linesize - #env.space - 1
    
    local cut = self.cut
    if row_del ~= "" then
        row_dels = row_dels:gsub("%s", row_del)
        table.insert(rows, cut(row_dels:gsub("[^%" .. row_del .. "]", row_del)))
    end
    
    local len = #result
    for k, v in ipairs(result) do
        local filter_flag, match_flag = 1, 0
        while #v < #colsize do table.insert(v, "") end
        env.event.callback("ON_PRINT_GRID_ROW", v, len)
        --adjust the title style(middle)
        if v[0] == 0 then
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
        end
        local row = cut(v, format_func, v[0] == 0 and head_fmt or fmt, v[0] == 0)
        
        if v[0] == 0 then
            row = row .. nor
        elseif env.printer.grep_text then
            row, match_flag = row:gsub(env.printer.grep_text, hl .. "%0" .. nor)
            if (match_flag == 0 and not env.printer.grep_dir) or (match_flag > 0 and env.printer.grep_dir) then filter_flag = 0 end
        end
        if filter_flag == 1 then table.insert(rows, row) end
        if not result[k + 1] or result[k + 1][0] ~= v[0] then
            if #row_del == 1 and filter_flag == 1 and v[0] ~= 0 then
                table.insert(rows, cut(row_dels))
            elseif v[0] == 0 then
                table.insert(rows, cut(title_dels, format_func, fmt))
            end
        end
    end
    
    if result[#result][0] > 0 and (row_del or "") == "" and (col_del or ""):trim() ~= "" then
        local line = cut(title_dels, format_func, fmt)
        line = line:gsub(" ", grid.title_del):gsub(col_del:trim(), function(a) return ('+'):rep(#a) end)
        table.insert(rows, line)
        table.insert(rows, 1, line)
    end
    self = nil
    return rows
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
    local all, grid_cfg = sql:match("(grid%s*=%s*(%b{}))")
    if grid_cfg then
        sql = sql:replace(all, '', true):gsub('/%*%s*%*/', '')
        grid_cfg = table.totable(grid_cfg)
    else
        grid_cfg = {}
    end
    return sql, grid_cfg
end

function grid.tostring(rows, include_head, col_del, row_del, rows_limit, pivot)
    if pivot then grid.pivot = pivot end
    if grid.pivot ~= 0 and include_head ~= false then
        rows = grid.show_pivot(rows)
        if math.abs(grid.pivot) == 1 then
            include_head = false
        else
            rows_limit = rows_limit and rows_limit + 2
        end
    end
    rows = grid.format(rows, include_head, col_del, row_del)
    rows_limit = rows_limit and math.min(rows_limit, #rows) or #rows
    env.set.force_set("pivot", 0)
    
    return table.concat(rows, "\n", 1, rows_limit)
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
    str = str .. grid.tostring(rows, include_head, col_del, row_del, rows_limit)
    if grid.bypassemptyrs and grid.bypassemptyrs:lower() == 'on' and size < (include_head and 2 or 1) then return end
    if test then env.write_cache("grid_output.txt", str) end
    print(str, '__BYPASS_GREP__')
    if suffix then print(suffix) end
end

function grid.merge(tabs, is_print, prefix, suffix)
    local strip = env.ansi.strip_len
    local function redraw(tab, cols, rows)
        local newtab = {_is_drawed = true, topic = tab.topic}
        local function push(line)newtab[#newtab + 1] = line end
        local actcols = strip(tab[#tab])
        local hspace = '|' .. space.rep(' ', cols - 2) .. '|'
        local max_rows = (tab.max_rows and tab.max_rows + 2 or rows) + 2
        if tab._is_drawed then
            local cspace = cols - actcols
            for rowidx, row in ipairs(tab) do
                if rowidx == #tab then
                    for i = rowidx + 1, rows do
                        push(hspace)
                    end
                end
                if cspace == 0 then
                    push(row)
                elseif cspace > 0 then
                    --push(row..cspace)
                    local right = cspace
                    local last = row:sub(-1)
                    push(row:sub(1, -2) .. string.rep(last == '+' and '-' or ' ', right) .. last)
                else
                    push(grid.cut(row, cols))
                end
            end
        else
            local diff = cols - actcols - 2
            local cspace = string.rep(' ', diff)
            local fmt = '+%s+'
            local head = fmt:format(string.rep('-', cols - 2))
            if (tab.topic or "") ~= "" then
                local topic = tab.topic
                push(fmt:format(topic:strip_ansi():cpad(cols - 2, '-',
                    function(left, str, right) return env.ansi.convert_ansi(string.format("%s$PROMPTCOLOR$%s$NOR$%s", left, (grid.cut(topic, cols - 2)), right)) end)))
            else
                push(head)
            end
            fmt = '|%s%s|'
            for rowidx, row in ipairs(tab) do
                push(fmt:format(diff >= 0 and row or grid.cut(row, cols - 2), cspace))
                if #newtab >= math.min(rows, max_rows) - 1 then break end
            end
            for i = #newtab + 1, rows - 1 do
                push(hspace)
            end
            push(head)
        end
        
        return newtab
    end
    
    local function _merge(tabs, is_wrap)
        local newtab = {}
        local maxwidth = 0
        local function push(line)
            newtab[#newtab + 1] = line
            maxwidth = math.max(maxwidth, strip(line))
        end
        local result = {}
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
                        tab, nexttab = redraw(tab, width1, maxlen), redraw(nexttab, width2, maxlen)
                        local fmt = '%s  %s'
                        for rowidx = 1, math.max(#tab, #nexttab) do
                            push(fmt:format(tab[rowidx], nexttab[rowidx]))
                        end
                    elseif sep == '+' then
                        local maxlen = math.max(height1, height2)
                        tab, nexttab = redraw(tab, width1, maxlen), redraw(nexttab, width2, maxlen)
                        local fmt = '%s%s%s'
                        for rowidx = 1, maxlen do
                            push(fmt:format(tab[rowidx]:sub(1, -2), (rowidx == 1 or rowidx == maxlen) and '+' or '|', nexttab[rowidx]:sub(2)))
                        end
                    else --sep=='-'
                        local maxlen = math.max(width1, width2)
                        tab, nexttab = redraw(tab, maxlen, height1), redraw(nexttab, maxlen, height2)
                        for _, row in ipairs(tab) do push(row) end
                        --push(string.rep(' ',maxlen))
                        for _, row in ipairs(nexttab) do push(row) end
                    end
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
                push(string.rep(' ', maxwidth))
            end
            if not result[i]._is_drawed then newtab._is_drawed = false end
            for _, row in ipairs(result[i]) do
                local spaces = maxwidth - strip(row)
                local s = spaces <= 0 and '' or string.rep(' ', spaces)
                push(row .. s)
            end
        end
        return newtab
    end
    
    local function format_tables(tabs, is_wrap)
        local result = {}
        local max = 30
        for idx = 0, max do
            local tab = tabs[idx]
            if type(tab) == "table" then
                if tab._is_drawed ~= nil then
                    result[#result + 1] = tab
                else
                    local found = false
                    for sub = 0, max do
                        local child = tab[sub]
                        if type(child) == "table" and (type(child.data) == "table" or type(child[#child]) == "table") then
                            found = true
                            break
                        end
                    end
                    
                    if found then
                        result[#result + 1] = format_tables(tab, false)
                    else
                        local topic, width, height, max_rows = tab.topic, tab.width, tab.height, tab.max_rows
                        local is_bypass = tab.bypassemptyrs
                        tab = grid.tostring(tab, true, " ", "", nil, tab.pivot):split("\n")
                        tab.topic, tab.width, tab.height, tab.max_rows = topic, width, height, max_rows
                        if is_bypass ~= 'on' and is_bypass ~= true or #tab > 2 then
                            result[#result + 1] = tab
                        end
                    end
                end
            elseif tab then
                result[#result + 1] = tab
            end
        end
        return _merge(result, is_wrap)
    end
    
    local result = format_tables(tabs, true)
    
    if is_print == true then
        local tab = {}
        local height = tabs.max_rows or #result + 1
        if prefix then tab[1] = prefix .. "\n" end
        for rowidx, row in ipairs(result) do
            tab[#tab + 1] = grid.cut(row, linesize)
            if #tab >= height - 1 then
                if rowidx < #result then tab[#tab + 1] = grid.cut(result[#result], linesize) end
                break
            end
        end
        
        local str = table.concat(tab, "\n")
        print(str, '__BYPASS_GREP__')
        if suffix then print(suffix) end
        return
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

return grid
