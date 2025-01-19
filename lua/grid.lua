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
    local l,siz
    if type(row) == "table" then
        local colbase = row.col_auto_size or grid.col_auto_size
        local cs = grid.colsize
        if cs then
            if colbase ~= 'auto' and colbase ~= 'trim' then
                for i, _ in ipairs(cs) do
                    l,siz,row[i] = tostring(row[i]):ulen(cs[i][1])
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
    siz = type(format_func) == "number" and format_func or linesize
    if #row > siz then
        l,siz,row=row:ulen(siz)
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
    local pt="[|),%] =]"
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
            if c=='' or (c:find(pt) and not p:find(pt)) then
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

function grid.show_pivot(rows, col_del,pivotsort)
    local keys = {}
    --if not title then print(table.dump(rows)) end
    local verticals=rows and rows.verticals and math.min(#rows,rows.verticals+1)
    rows=rows.data or rows
    local colinfo=rows.colinfo or rows[1] and rows[1].colinfo or {}
    local title = rows[1]
    local maxsize = grid.col_size
    local pivot = math.abs(grid.pivot) + 1
    local del = grid.title_del
    del = (del == "-" and "=") or (del == "=" and "||") or (del == "." and ":") or del
    del = ' ' .. del .. ' '
    --if not grid.col_del:match("^[ \t]+$") then del="" end
    if pivot > #rows then pivot = #rows end
    if pivot > 2 then del='' end
    local maxlen = 0
    local len1,len2,nv
    local tops={{}}
    local _, value
    local max_cols=12
    local null_value=env.set.NULL and env.set.get('NULL') or ''
    local autohide=grid.autohide
    if #rows<2 and (autohide=='on' or autohide=='all') then return {} end 

    local col_wrap = grid.col_wrap
    local linesize = grid.linesize
    if linesize <= 10 then linesize = math.max(60,getScreenWidth(console) - (#env.space) * 2) end
    if maxsize>=1024 and col_wrap==0 then
        col_wrap=linesize
    end

    local function get_value(title,r,c)
        if not colinfo[c] then colinfo[c]={column_name = title} end
        _, value = grid.format_column(true, type(title) == "table" and title or colinfo[c], tonumber(rows[r][c]) or rows[r][c], r-1)
        len1,len2,nv=tostring(value or null_value):trim():ulen(maxsize)
        if col_wrap > 0 and len2 > col_wrap and not nv:sub(1,1024):find('\n',1,true) then
            value,len1,len2=grid.line_wrap(nv,col_wrap)
            nv=table.concat(value,'\n')
        end
        max_cols=max_cols<len2 and len2 or max_cols
        return nv
    end

    for k, v in ipairs(title) do
        keys[v] = k
        len1,len2,nv=v:ulen(maxsize)
        maxlen=maxlen < len2 and len2 or maxlen
        if verticals then
            for i=1,math.min(30,verticals-1) do
                if not tops[i] then tops[i]={} end
                tops[i][k]=get_value(v,i+1,k)
            end
        end
    end

    local color = env.ansi.get_color
    local nor, hor = color("NOR"), color("HEADCOLOR")

    local r = {}
    if verticals and verticals>1 then
        maxlen=maxlen+3
        local width=console:getScreenWidth() - maxlen - 2 - #env.space*2
        local cname='Column Value'
        r[1]={'|',"#",'|','Column Name',cname}
        local siz
        local titles={}
        for k, t in ipairs(title) do
            len1,len2,nv=grid.format_title(t):rtrim():ulen(maxsize)
            titles[k]=("%s %-" .. (maxlen+len1-len2) .. "s%s %s"):format(hor, nv, nor, '=')
        end
        local seq_size=#tostring(verticals)+3
        local group_rows=math.min(verticals-1,math.floor(1.0*(width+seq_size)/(max_cols+seq_size)))
        for j=2,group_rows do
            siz=#r[1]
            r[1][siz+1],r[1][siz+2],r[1][siz+3],r[1][siz+4]="|","#",'|',cname
        end
        
        local row
        local st,ed
        local empties={}
        for i=1,verticals-1 do
            if group_rows<2 or math.fmod(i,group_rows)==1 then st,ed=#r,#r+#titles end
            for j,v in ipairs(titles) do
                local idx=st+j
                nv=tops[i] and tops[i][j] or get_value(t,i+1,j)
                empties[idx]=(empties[idx] or 0) + (nv~='' and nv~=null_value and 1 or 0)
                if not r[idx] then
                    r[idx]={'|',i,'|',v,nv}
                else
                    siz=#r[idx]
                    r[idx][siz+1],r[idx][siz+2],r[idx][siz+3],r[idx][siz+4]='|',i,'|',' '..nv
                end
            end
            if group_rows<2 or i==verticals-1 or math.fmod(i,group_rows)==0 then
                if autohide=='col' or autohide=='all' then
                    for j=ed,st+1,-1 do
                        if empties[j]==0 then table.remove(r,j) end
                    end
                end
                r[#r+1]={'$HIY$-$NOR$'} 
            end
        end
        return r
    end
    
    pivotsort=(pivotsort or grid.pivotsort):lower()
    if pivotsort == "on" then table.sort(title) end
    local head=pivotsort=='head' and tostring(title[1]):lower() or (pivotsort~='on' and pivotsort~='off') and pivotsort or nil
    local _, value
    for k, v in ipairs(title) do
        len1,len2,nv=v:ulen(maxsize)
        local row={("%s%-" .. (maxlen+len1-len2) .. "s %s%s"):format(hor, grid.format_title(nv)..(v:lower()==head and ' =>' or ''), nor, del)}
        
        for i = 2, pivot, 1 do
            row[#row+1]=get_value(v,i,keys[v])
        end

        local print_=not colinfo[keys[v]] or not colinfo[keys[v]].no_print
        if pivot==2 and row[#row]=='' and (autohide=='col' or autohide=='all') then
            print_=false
        end
        if v:lower()==head then
            table.insert(r,1, row)
        elseif print_ then
            table.insert(r, row)
        end
    end
    
    if pivot == 2 and grid.pivot > 0 then
        for i = 1, #r, 2 do
            if r[i + 1] then
                local k, v = '. ' .. r[i + 1][1], r[i + 1][2]
                if type(v) == "string" then
                    v:gsub('[%s\r\n\t]+$', ''):gsub('\r?\n', function() k = k .. '\n.' end)
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
    elseif grid.pivot > 0 and #r>0 and head==nil then
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
        local v1, v2 = tonumber(value)
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
function grid:add(row)
    if type(row) ~= "table" then return end
    local rs = {_org = {}}
    local result, headind, colsize = self.data, self.headind, self.colsize
    local title_style = grid.title_style
    local colbase = self.col_auto_size or grid.col_auto_size
    local autohide= self.autohide or self.bypassemptyrs or grid.autohide
    local rownum = grid.row_num
    local null_value=env.set.NULL and env.set.get('NULL') or ''
    local maxsize = grid.col_size
    grid.colsize = self.colsize
    for k, v in pairs(row) do rs[k] = v end
    if self.headind == -1 then
        self.headind = 1
        return
    end
    if rownum == "on" then
        table.insert(rs, 1, headind == 0 and "#" or headind)
    end
    if not self.break_groups then self.break_groups={} end
    if headind == 0 then
        if rownum == "on" and rs.colinfo then table.insert(rs.colinfo, 1, {is_number = true}) end
        self.colinfo = rs.colinfo
    end
    
    local lines = 1
    rs[0] = headind

    local cols = #result > 0 and #result[1] or #rs
    local rsize, l, len=0
    --run statement
    local split='['..(headind == 0 and '' or ' ')..'\a\r\f\b\v]*\n[\a\r\f\b\v]*'
    local function strip_len(str)
        if autohide=='all' or autohide=='col' then
            local len=#(str:ltrim())
            if len==0 or str==null_value then return 0,'' end
        end
        return #str,str
    end
    for k = 1, cols do
        local v = rs[k]
        if type(v)=='userdata' then v=tostring(v) end
        rs._org[k] = v
        if k > grid.maxcol then break end
        local csize,usize,v1, is_number = 0,0,v
        local st,ed
        if not colsize[k] then colsize[k] = {0, 1} end

        if not self.colinfo then self.colinfo={} end
        if not self.colinfo[k] then
            local info={column_name = #result > 0 and result[1]._org[k] or tostring(v),numbers=0}
            self.colinfo[k]=info
            self.colinfo[info.column_name:upper()]=k
        elseif self.colinfo[k].is_number and type(v)=='string' then
            v,st,ed=v:from_ansi()
        end

        is_number, v1 = grid.format_column(self.include_head, self.colinfo[k], v, #result,self,headind,rs)

        if tostring(v) ~= tostring(v1) then v = v1 end
        if st or ed then v=(st or '')..v..(ed or '') end
        if colsize[k][3] and type(v)=='string' and colsize[k][3]:find(v,1,true) then
            csize,colsize[k][3]=strip_len(colsize[k][3])
        elseif is_number and headind>0 then
            l,csize=0,strip_len(tostring(v))
            if csize>0 then
                l,csize = tostring(v):ulen()
            else
                v=''
            end
            colsize[k][3],colsize[k][4]=nil
            self.colinfo[k].numbers=(self.colinfo[k].numbers or 0)+1
        elseif type(v) ~= "string" or v == "" or (v==null_value) then
            v=tostring(v)
            csize = strip_len(v)
            self.colinfo[k].nulls=(self.colinfo[k].nulls or 0)+1
        else
            if headind>0 then self.colinfo[k].chars=(self.colinfo[k].chars or 0)+1 end
            local grp = empty
            v = v:convert_ansi()
            if headind == 0 then
                v,l = v:gsub('[\n\r]+',''):gsub("([^|]+)%c*|%c*([^|]+)", function(a, b)
                        local len11,len12,len21,len22
                        len11,len12,a=a:ulen(math.min(99,maxsize))
                        len21,len22,b=b:ulen(math.min(99,maxsize))
                        local max_len = math.max(len12, len22)
                        usize=math.max(len11, len21)
                        csize=max_len
                        grp[1]=reps(' ', math.floor((max_len - len12) / 2))..a..reps(' ', math.ceil((max_len - len12) / 2))
                        grp[2]=reps(' ', math.floor((max_len - len22) / 2))..b..reps(' ', math.ceil((max_len - len22) / 2))
                        return table.concat(grp,'\n')
                end,1)
                local v1=v:strip_ansi()
                if #v1<=3 and v1:find('^%W+$') and v1~='#' and v1~='%' then 
                    colsize[k][3]=v
                elseif v=="" then
                    colsize[k][3]=""
                end
                if title_style ~= "none" and self.include_head then
                    v = grid.format_title(v)
                end
            else
                v=v:sub(1,1048576*4):rtrim()
                for p in v:gsplit(split) do
                    p=p:gsub('%c',printables)
                    --deal with unicode chars
                    l, len, p = p:ulen(maxsize)
                    grp[#grp + 1] = p
                    usize=usize<l and l or usize
                    if len==0 and p~='' then len=1 end
                    csize=csize < len and len or csize
                end

                if colsize[k][3] and v~=colsize[k][3] and v~="" then
                    if k==1 then
                        local v1=v:strip_ansi()
                        if not v1:match('^%W$') then
                            colsize[k][3]=nil
                        else
                            rsize=1
                        end
                    else
                        colsize[k][3]=nil
                    end
                end

                if #grp==1 then
                    v=grp[1]
                    local col_wrap = grid.col_wrap
                    if cols==1 and maxsize>=1024 and headind<2 then
                        local linesize = self.linesize
                        if linesize <= 10 then linesize = getWidth(console) - (#env.space) * 2 end
                        if usize>math.max(linesize,maxsize)  then
                            col_wrap=col_wrap==0 and linesize or math.min(linesize,col_wrap)
                        end
                    end
                    if col_wrap > 0 and usize > col_wrap then
                        grp,usize,csize=grid.line_wrap(v,col_wrap)
                        empty={}
                    end
                end
            end

            if lines < #grp then lines = #grp end
            if not grp[1] then
                usize,csize,v=v:ulen(math.min(maxsize,headind==0 and 99 or maxsize))
            elseif #grp>1 then
                v,empty=grp,{}
            else
                v=grp[1]
                clear(empty)
            end

            if csize==0 and v~='' then csize=1 end

            if self.colinfo[k].is_number then
                colsize[k][2] = 1
            elseif headind > 0 then
                colsize[k][2] = -1
            end
        end
        
        rs[k] = v
        
        if grid.pivot == 0 and headind == 0 and (colbase == "body" or colbase == "trim") and self.include_head then 
            colsize[k][1] = 0
            colsize[k].__trimsize=(colbase == "trim" and csize) or 0
        elseif colsize[k][1] < csize and not (self.include_head and grid.pivot == 0 and headind~=0 and colbase=='head') then
            if colsize[k].__trimsize and colsize[k][1]==0  then
                if v~=null_value then
                    csize=math.max(csize,colsize[k].__trimsize)
                else
                    csize=colsize[k][1]
                end
            end
            colsize[k][1] = csize
        end
        colsize[k].org_size=math.max(colsize[k].org_size or 0,csize)
        if autohide=='col' or autohide=='all' then
            if headind==0 then 
                colsize[k].head_size, colsize[k][1]=colsize[k][1],0
                csize=0
            elseif colsize[k][1]>0 and colsize[k].head_size then
                csize=math.max(colsize[k][1],colsize[k].head_size)
                colsize[k][1],colsize[k].head_size=csize
            end
        end
        rsize = not colsize[k][3] and rsize < csize and csize or rsize
    end
    
    local row,tmp
    local function add_row(r)
        result[#result + 1] = r
        tmp=r
    end

    rs.rsize=rsize
    if rsize>0 or autohide=='off' or headind==0 then
        if lines == 1 then
            add_row(rs)
        else
            for i = 1, lines, 1 do
                local r = table.new(#rs, 3)
                r[0], r._org = rs[0], rs._org
                for k = 1, cols do
                    local v = rs[k]
                    if type(v) ~= "table" then
                        rs[k] = table.new(lines, 0)
                        rs[k][1] = v
                        v = rs[k]
                    end
                    local siz=lines-#v
                    for j = 1, siz do
                        if headind == 0 then
                            local org=v[1]
                            if #org>0 and org==colsize[k][3] then
                                if (k==1 or rs[k-1][siz-j+1]:trim()=='') and (type(rs[k+1])~='table' or rs[k+1][siz-j+1]:trim()=='') then
                                    table.insert(v, 1,'')
                                else
                                    table.insert(v, 1, colsize[k][3] or '')
                                end
                            else
                                table.insert(v, 1, colsize[k][3] or '')
                            end
                        else
                            v[#v + 1] = ""
                        end
                    end
                    r[k] = v[i] == nil and "" or v[i]
                end
                r.rsize=rsize
                add_row(r)
            end
            rs=tmp
        end
    end
    
    self.headind = headind + (rsize==0 and autohide~='off' and headind>0 and 0 or 1)
    local sep=self.break_groups.__SEP__
    if headind>1 and sep~=nil then
        local row={}
        for k,v in ipairs(self.colinfo) do
            if self.break_groups[v.column_name:upper()] then
                row[k]=sep
                --if rs[k]=='' then
                --    rs[k]=self.break_groups[v.column_name:upper()] 
                --end
            end
        end
        self.break_groups.__SEP__=nil
        result=self:add(row)
        row=table.remove(result)
        row.sep=sep
        table.insert(result,#result,row)
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

function grid:wellform(col_del, row_del)
    self.break_groups=nil
    local result, colinfo, colsize = self.data,self.colinfo, self.colsize
    if #result==0 or (grid.autohide== 'on' or grid.autohide== 'all') and result[#result][0]==0 then return {},{}  end
    local rownum = grid.row_num
    local siz, rows, output = #result, table.new(#result + 1, 0), table.new(#result + 1, #result[1])
    if siz == 0 then return rows end
    local fmt = ""
    local title_dels, row_dels = {}, ""
    col_del = col_del or grid.col_del
    row_del = (row_del or grid.row_del):sub(1, 1)
    local pivot = grid.pivot
    local indx = rownum == "on" and 1 or 0
    fmt = col_del:ltrim()
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
            end
            table.insert(colsize, idx + 1, {7, 1})
            table.insert(colinfo, idx + 1, {column_name=name,is_number=true})
        end
        self.ratio_cols = nil
    end

    --Generate row formatter
    local color = env.ansi.get_color
    local nor, hor, hl = color("NOR"), color("HEADCOLOR"), color("GREPCOLOR")
    local head_fmt,max_siz = fmt,0
    local seps={}
    local prev,next,prev_sep,prev_none_zero,del={},nil,-1,-1
    local cols=#colsize
    local function calc_col_sep(sep,row_sep)
        return row_sep:find('[~#=%-%*%+]') and sep:gsub('[|:]','+'):gsub('[\\/]',row_sep) or sep
    end

    row_dels = calc_col_sep(fmt,row_del)
    for k, v in ipairs(colsize) do
        if v[2]==1 or (not colinfo[k].is_number and (colinfo[k].chars or 0)==0 and (colinfo[k].numbers or 0)>0) then
            colinfo[k].is_number=true
            v[2]=1
        end
        if max_siz==0 and k>1 then v[3]=nil end
        siz,seps[k]=v[1],v[3]
        if seps[k] then
            if prev_none_zero<=prev_sep and k>1 then 
                siz=0
                v[3]=nil
            end
            prev_sep=k
        elseif siz>0 then
            prev_none_zero=k
        end
        
        v[1] = siz
        next = colsize[k+1] or {}
        del  = (seps[k] or next[3] or next[1]==0) and ""  or " "

        if siz==0 and (prev[3] or k==1) then del='' end
        if (del~="" and pivot == 0) or (pivot ~= 0 and k ~= 1 + indx and (pivot ~= 1 or k ~= 3 + indx)) then 
            del = col_del
        end

        if k == cols then del = del:rtrim() end

        if siz == 0 then
            fmt = fmt .. "%s".. (k==cols and nor or '').. del
            head_fmt = head_fmt .. "%s".. del
            seps[k] = ''
        else
            fmt = fmt .. "%" .. (siz * v[2]) .. "s" .. (k==cols and nor or '').. del
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
        title_dels[k]=(v[3] and calc_col_sep(v[3],grid.title_del)) or reps(not is_empty and grid.title_del or " ", siz)
        
        if row_del ~= "" then
            row_dels = row_dels .. row_del:rep(siz) .. calc_col_sep(del,row_del)
        end
        prev=v
        max_siz = max_siz < siz and siz or max_siz
    end
    if prev_none_zero<=prev_sep and prev_sep<#colsize then 
        for k,v in pairs(seps) do
            if k>=prev_none_zero and #v>0 then 
                seps[k],title_dels[k]='',''
            end
        end
    end

    if max_siz==0 then
        if grid.autohide=='off' or grid.autohide=='col' then
            for k,v in ipairs(colsize) do
                v[1]=v.org_size
                max_siz=max_siz+v[1]
            end
        end
        if max_siz>0 then
            return self:wellform(col_del, row_del)
        else
            return {},{}
        end
    end

    linesize = self.linesize

    if linesize <= 10 then linesize = getWidth(console) end
    linesize = linesize - #env.space - 1
    
    local cut = self.cut
    if row_del ~= "" then
        output[#output+1]=row_dels:gsub("%s", row_del)
        rows[#rows+1]=cut(output[#output])
    end

    if grid._merge_mode and col_del~=' ' and #col_del>0 then
        head_fmt=head_fmt:sub(2,-2)
        fmt=fmt:sub(2,-2)
    end
    
    local len = #result
    for k, v in ipairs(result) do
        local filter_flag, match_flag = 1, 0
        while #v < #colsize do v[#v+1]='' end
        local is_row_sep
        if v.sep then
            is_row_sep=v.sep
        elseif v[0]~=0 and v.rsize==1 and type(v[1])=='string' then 
            local v1=v[1]:strip_ansi()
            local v2=tostring(v[2] or ''):strip_ansi()
            local v3=tostring(v[3] or ''):strip_ansi()
            if v1:find('[~#|=@_:<>&/\\%$%-%+%*%.]') and
               (v2=='' or v2==v1 or v2:find('^%W+$')) and
               (v3=='' or v3==v1 or v3:find('^%W+$') or v[3]==seps[3])
            then
                is_row_sep=v1
            end
        end

        for k1,v1 in pairs(seps) do
            if not (k1==1 and is_row_sep) then
                if v[0]>0 or not(v[k1]=='' and (v[k1+1] or '')=='' and (k1==1 or v[k1-1]=='')) then
                    v[k1]=is_row_sep or v1
                end
            end
        end
        --adjust the title style(middle)
        local fmt1
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
        elseif is_row_sep then
            fmt1=calc_col_sep(fmt,is_row_sep)
            local c=is_row_sep
            for k1,v1 in ipairs(title_dels) do
                v[k1]=v1:sub(1,1)==grid.title_del and v1:gsub('.',c) or v1
            end
            if output[#output]==row_dels then
                output[#output],rows[#rows]=nil
            end
        end

        v.format_func,v.fmt=format_func,v[0] == 0 and head_fmt or fmt1 or fmt
        local row = cut(v, v.format_func,v.fmt, v[0] == 0)

        if v[0] == 0 then
            row = row .. nor
        elseif env.printer.grep_text then
            row, match_flag = row:gsub(env.printer.grep_text, hl .. "%0" .. nor)
            if (match_flag == 0 and not env.printer.grep_dir) or (match_flag > 0 and env.printer.grep_dir) then filter_flag = 0 end
        end

        output[#output+1]=v

        if filter_flag == 1 then
            rows[#rows+1]=row 
        end
        
        if not result[k + 1] or result[k + 1][0] ~= v[0] then
            if not is_row_sep and #row_del == 1 and filter_flag == 1 and v[0] ~= 0 then
                row_dels=row_dels:gsub('%s',row_del)
                rows[#rows+1]=cut(row_dels)
                output[#output+1]=row_dels
            elseif v[0] == 0 then
                output[#output+1]=format_func(calc_col_sep(fmt,grid.title_del), table.unpack(title_dels))
                rows[#rows+1]=cut(output[#output])
            end
        end
    end
    
    if not grid._merge_mode and result[#result][0] > 0 and (row_del or "") == "" and (col_del or ""):trim() ~= "" then
        local line = cut(title_dels, format_func, fmt)
        line = line:gsub(" ", grid.title_del):gsub(col_del:trim(), function(a) return ('+'):rep(#a) end)
        rows[#rows+1]=line
        output[#output+1]=line
        table.insert(rows, 1, line)
        table.insert(output,1, line)
    end
    output.len=len
    output.colinfo,(output[1] or {}).colinfo=colinfo,colinfo

    return rows,output
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

function grid.merge(tabs, is_print, prefix, suffix)
    local function strip(str)
        local l1,l2 = str:ulen()
        return l2
    end
    local footprint_pattern=env.ansi.mask('UDL','(.-)','NOR'):gsub('%[','%%[')
    local function redraw(tab, cols, rows)
        local newtab = {_is_drawed = true, topic = tab.topic or tab.title,footprint=tab.footprint or tab.bottom}
        local function push(line) newtab[#newtab + 1] = line end
        local actcols = strip(tab[#tab])
        local hspace = '|' .. space.rep(' ', cols - 2) .. '|'
        local max_rows = (tab.max_rows and tab.max_rows + 2 or rows) + 2
        if tab._is_drawed then
            local cspace = cols - actcols
            local do_push=function(row)
                if cspace == 0 then
                    push(row)
                elseif cspace > 0 then
                    --push(row..cspace)
                    local right = cspace
                    local last = row:sub(-1)
                    push(row:sub(1, -2) .. reps(last == '+' and '-' or ' ', right) .. last)
                else
                    push(grid.cut(row, cols))
                end
            end
            for rowidx, row in ipairs(tab) do
                if rowidx == #tab then
                    local line=row:gsub(footprint_pattern,function(c) return reps(' ',#c) end)
                    line=line:gsub('.',function(c) return c=='+' and '|' or c=='-' and ' ' or c end)
                    for i = rowidx + 1, rows do
                        do_push(line)
                    end
                elseif rowidx>=rows and tab.height==0 and tab.min_height<rows then
                    do_push('+'..reps('-',actcols-2)..'+')
                    break
                end
                do_push(row)
            end
        else
            local diff = cols - actcols - 2
            local cspace = reps(' ', diff)
            local fmt = '+%s+'
            local head = fmt:format(reps('-', cols - 2))
            local conv=env.ansi.convert_ansi
            if (tab.topic or "") ~= "" then
                local topic,st,ed = tab.topic:from_ansi()
                push(fmt:format(topic:match('[^\n]+'):cpad(cols - 2, '-',
                    function(left, str, right) 
                        return conv(("%s$PROMPTCOLOR$%s$NOR$%s"):format(left, grid.cut(topic, cols - 2):to_ansi(st,ed), right)) 
                    end)))
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
            if (tab.footprint or "") ~= "" then
                local footprint,st,ed = tab.footprint:from_ansi()
                footprint=footprint:match('[^\n]+'):cpad(cols - 2, '-',
                function(left, str, right)
                    return conv(("%s$UDL$%s$NOR$%s"):format(left or '', (grid.cut(footprint, cols - 2)):to_ansi(st,ed), right or '')) 
                end)
                push('+'..footprint..'+')
            else
                push(head)
            end
        end
        
        return newtab
    end
    
    local frames={}
    local printsize=env.set and env.set.get('PRINTSIZE') or 512
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

    local function format_tables(tabs, is_wrap)
        local autohide=grid.autohide
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
                        local topic,footprint,width, height, max_rows = tab.topic,tab.footprint,tab.width, tab.height, tab.max_rows
                        local is_bypass1,is_bypass2,autosize1,autosize2 = grid.autohide,tab.autohide or tab.bypassemptyrs,grid.col_auto_size,tab.autosize
                        if autosize2 then grid.col_auto_size=autosize2 end
                        is_bypass2=is_bypass2==true and 'on' or is_bypass2==false and 'off' or is_bypass2 or is_bypass1
                        grid.autohide=is_bypass2
                        grid._merge_mode=true
                        local _,output=grid.tostring(tab, true,tab.colsep, "", nil, tab.pivot,tab.pivotsort)
                        grid._merge_mode=nil
                        if autosize2 then grid.col_auto_size=autosize1 end
                        grid.autohide=is_bypass1
                        tab={}
                        for k,row in ipairs(output) do
                            local filter_flag,match_flag=1
                            if type(row)=="table" then
                                local is_body=not row[0] or row[0]>0
                                row=row.format_func(row.fmt, table.unpack(row))
                                if is_body and env.printer.grep_text then
                                    row, match_flag = row:gsub(env.printer.grep_text, hl .. "%0" .. nor)
                                    if (match_flag == 0 and not env.printer.grep_dir) or (match_flag > 0 and env.printer.grep_dir) then 
                                        filter_flag = 0
                                    end
                                end
                            end
                            if filter_flag==1 then tab[#tab+1]=row end
                        end
                        
                        tab.topic, tab.footprint,tab.width, tab.height, tab.max_rows = topic, footprint,width, height, max_rows
                        if #tab > 0 then
                            result[#result + 1] = tab
                        end
                    end
                end
            elseif tab then
                result[#result + 1] = tab
            end
        end
        grid.autohide=autohide
        return _merge(result, is_wrap)
    end

    local result = format_tables(tabs, true)

    if is_print == true or is_print=='plain' then
        local tab = {}
        local height = tabs.max_rows or #result + 1
        local space=env.printer.top_mode==true and env.space or ''
        if prefix then 
            tab[1] = space..prefix:convert_ansi()
            env.event.callback("ON_PRINT_GRID_ROW",tab[1])
        end
        for rowidx, row in ipairs(result) do
            tab[#tab + 1] = space..grid.cut(row, linesize):convert_ansi()
            env.event.callback("ON_PRINT_GRID_ROW",row,{rowidx,#result})
            if #tab >= height - 1 then
                if rowidx < #result then 
                    tab[#tab + 1] = space..grid.cut(result[#result], linesize)
                    env.event.callback("ON_PRINT_GRID_ROW",tab[#tab],{rowidx,#result})
                end
                break
            end
        end
        if env.printer.top_mode==true then
            tab[#tab+1]=''
            return console:display(tab)
        end
        
        local str = table.concat(tab, "\n")
        if is_print==true then
            env.printer.print_grid(str)
            if suffix then print(suffix) end
            return
        end
        return str,table.concat(result,'\n')
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
