--Usage: print / save a 2-D arrary
local env,pairs,ipairs=env,pairs,ipairs
local math,table,string,class,event=env.math,env.table,env.string,env.class,env.event
local grid=class()
local console=console
local getWidth=console.getBufferWidth

local params={
    [{'HEADSEP','HEADDEL'}]={name="title_del",default='-',desc="The delimiter to devide header and body when printing a grid"},
    [{'COLSEP','COLDEL'}]={name="col_del",   default=' ',desc="The delimiter to split the fields when printing a grid"},
    [{'ROWSEP','ROWDEL'}]={name="row_del",   default=''  ,desc="The delimiter to split the rows when printing a grid"},
    COLWRAP={name="col_wrap", default=0,desc="If the column size is larger than COLDEL, then wrap the text",range="0 - 32767"},
    COLAUTOSIZE={name="col_auto_size", default='auto',desc="Define the base of calculating column width",range="head,body,auto"},
    ROWNUM={name="row_num",   default="off",desc="To indicate if need to show the row numbers",range="on,off"},
    HEADSTYLE={name="title_style",default="none",desc="Display style of the grid title",range="upper,lower,initcap,none"},
    PIVOT={name="pivot",default=0,desc="Pivot a grid when next print, afterward the value would be reset",range="-30 - +30"},
    PIVOTSORT={name="pivotsort",default="on",desc="To indicate if to sort the titles when pivot option is on",range="on,off"},
    MAXCOLS={name="maxcol",default=1024,desc="Define the max columns to be displayed in the grid",range="4-1024"},
    DIGITS={name="digits",default=38,desc="Define the digits for a number",range="0 - 38"},
    SEP4K={name="sep4k",default="off",desc="Define whether to show number with thousands separator",range="on,off"},
    HEADING={name="heading",default="on",desc="Controls printing of column headings in reports",range="on,off"},
    LINESIZE={name="linesize",default=0,desc="Define the max chars in one line, other overflow parts would be cutted.",range='0-32767'},
    BYPASSEMPTYRS={name="bypassemptyrs",default="off",desc="Controls whether to print an empty resultset",range="on,off"}
    --NULL={name="null_value",default="",desc="Define display value for NULL."}
}

local function toNum(v)
    if type(v)=="number" then
        return v
    elseif type(v)=="string" then
        return tonumber((v:gsub(",",'')))
    else
        return tonumber(v)
    end
end

function grid.set_param(name,value)
    if (name=="TITLEDEL" or name=="ROWDEL") and #value>1 then
        return print("The value should be only one char!")
    elseif name=="COLWRAP" and value>0 and value<30 then
        return print("The value cannot be less than 30 !")
    end
    grid[grid.params[name].name]=value
    return value
end

function grid.format_title(v)
    if grid.title_style=="none" then
        return v
    end
    if not v[grid.title_style] then
        string.initcap=function(v)
            return (' '..v):lower():gsub("([^%w])(%w)",function(a,b) return a..b:upper() end):sub(2)
        end
    end
    return v[grid.title_style](v)
end

local linesize
function grid:cut(row,format_func,format_str)
    if type(row)=="table" then
        local colbase=self.col_auto_size
        local cs=self.colsize
        if colbase~='auto' then
            for i,var in ipairs(cs) do
                row[i]=tostring(row[i]):sub(1,cs[i][1])
            end
        end
        row=format_func(format_str,table.unpack(row))
    end
    
    if #row>linesize then
        local tab,len,count,clen,ulen={},-linesize,0
        for piece,pattern in row:gsplit("(\27%[[%d;]*[mK])") do
            clen,ulen=piece:ulen()
            len,count = len + ulen,count +1
            tab[#tab+1] = len<0 and piece or piece:sub(1,ulen-len)
            if (pattern or "")~="" then tab[#tab+1]=pattern end
            if len>=0 then
                tab[#tab+1]=env.ansi.get_color('NOR')
                break 
            end
        end
        return table.concat(tab,'')
    end
    return row..env.ansi.get_color('NOR')
end

local s_format="%s%%%s%ss%s"
function grid.fmt(format,...)
    local idx,v,lpad,rpad,pad=0,nil
    local args={...}
    local fmt= format:gsub("(%%(-?)(%d*)s)",
        function(g,flag,siz)
            idx=idx+1
            if siz=="" then return g end
            siz=tonumber(siz)
            lpad,rpad,pad="","",""
            v=args[idx]
            if not v or type(v)~="string" then return g end
            local chars,length=v:ulen()
            local strips=#v-v:strip_len()
            chars=length-chars+strips
            if chars>0 then siz=siz+chars end
            if siz>99 then
                pad=string.rep(" ",siz-length+strips) or ""
                if flag~="-" then
                    lpad=pad
                else
                    rpad=pad
                end
                siz=''
            end
            return s_format:format(lpad,flag,tostring(siz),rpad)
        end)
    --print('new',format,',',fmt)
    return fmt:format(...)
end

function grid.format(rows,include_head,col_del,row_del)
    local this
    if rows.__class then
        this=rows
    else
        this=grid.new(include_head)
        for i,rs in ipairs(rows) do
            this:add(rs)
        end
    end
    return this:wellform(col_del,row_del)
end

function grid.tostring(rows,include_head,col_del,row_del,rows_limit)
    if grid.pivot ~= 0 and include_head~=false then
        rows=grid.show_pivot(rows)
        if math.abs(grid.pivot)==1 then
            include_head=false
        else
            rows_limit=rows_limit and rows_limit+2
        end
    end
    rows=grid.format(rows,include_head,col_del,row_del)
    rows_limit=rows_limit and math.min(rows_limit,#rows) or #rows
    env.set.force_set("pivot",0)

    return table.concat(rows,"\n",1,rows_limit)
end


function grid.sort(rows,cols,bypass_head)
    local head
    local sorts={}
    local has_header
    if rows.__class then rows,has_header=rows.data,rows.include_head end
    for ind in tostring(cols):gsub('^,*(.-),*$','%1'):gmatch("([^,]+)") do
        local col,l
        if tonumber(ind) then
            ind=tonumber(ind)
            col=math.abs(ind)
            l=ind
        elseif type(ind)=="string" and bypass_head==true then
            if ind:sub(1,1)=='-' then
                col=ind:sub(2)
                l=-1
            else
                col=ind
                l=1
            end
            for k,v in ipairs(rows[1]) do
                if col:upper()==tostring(v):upper() then
                    col=k
                    break
                end
            end
            if type(col)~="number"  then
                return rows
            end
        else
            return rows
        end
        sorts[#sorts+1]=function() return col,l end
    end

    if bypass_head or has_header then head=table.remove(rows,1) end

    table.sort(rows,function(a,b)
        for ind,item in ipairs(sorts) do
            local col,l=item()
            local a1,b1= a._org and a._org[col] or a[col],b._org and b._org[col] or b[col]
            
            if a1==nil then
                return false
            elseif b1==nil then
                return true
            else
                local a2,b2=toNum(a1),toNum(b1)
                if a2 and b2 then 
                    a1,b1=a2,b2
                else
                    a1,b1=tostring(a1),tostring(b1)
                end
            end

            if type(a1)=="string" then 
                a1,b1=a1:strip_ansi() ,b1:strip_ansi() 
            end

            if a1~=b1 then
                if l<0 then return a1>b1 end
                return a1<b1
            end
        end
        return false
    end)

    if head then table.insert(rows,1,head) end
    return rows
end

function grid.show_pivot(rows,col_del)
    local title=rows[1]
    local keys={}

    local pivot=math.abs(grid.pivot)+1
    local del=grid.title_del
    del=(del=="-" and "=") or (del=="=" and "||") or (del=="." and ":") or del
    del=' '..del..' '
    --if not grid.col_del:match("^[ \t]+$") then del="" end
    if pivot>#rows then pivot=#rows end

    local maxlen=0
    for k,v in ipairs(title) do
        keys[v]=k
        if maxlen<v:len() then
            maxlen=v:len()
        end
    end

    local r={}
    local color=env.ansi.get_color
    local nor,hor=color("NOR"),color("HEADCOLOR")
    if grid.pivotsort=="on" then table.sort(title) end
    for k,v in ipairs(title) do
        table.insert(r,{("%s%-"..maxlen.."s %s%s "):format(hor,grid.format_title(v),nor,del)})
        for i=2,pivot,1 do
            table.insert(r[k],tostring(rows[i][keys[v]]):trim())
        end
    end

    if pivot==2 and grid.pivot>0 then
        for i=1,#r,2 do
            if r[i+1] then
                local k,v='. '..r[i+1][1],r[i+1][2]
                if type(v)=="string" then
                    v:gsub('[%s\r\n\t]+$',''):gsub('[\n\r]',function() k=k..'\n.' end)
                end
                table.insert(r[i],k)
                table.insert(r[i],v)
            else
                table.insert(r[i],"")
                table.insert(r[i],"")
            end
        end

        for i=1024,0,-2 do
            if r[i] then table.remove(r,i) end
        end
        grid.pivot=1
    elseif grid.pivot>0 then
        local titles={" "}
        for i=2,#r[1],1 do
            titles[i]=' #'..(i-1)
        end
        table.insert(r,1,titles)
    end
    return r
end

function grid:ctor(include_head)
    if include_head==nil then 
        include_head=(grid.heading or "on")=="on" and true or false
        self.headind=include_head==false and -1 or 0
    else
        self.headind=include_head==false and 1 or 0
    end
    self.include_head=self.headind == 0 and true or false
    self.colsize=table.new(255,0)
    self.data=table.new(1000,0)
end

function grid:add(row)
    if type(row)~="table" then return end
    local rs={_org={}}
    local result,headind,colsize=self.data,self.headind,self.colsize
    local title_style=grid.title_style
    local colbase=grid.col_auto_size
    local rownum=grid.row_num
    for k,v in pairs(row) do rs[k]=v end
    if self.headind==-1 then
        self.headind=1
        return
    end
    if rownum == "on" then
        table.insert(rs,1,headind==0 and "#" or headind)
    end

    if headind==0 then
        if rownum == "on" and rs.colinfo then table.insert(rs.colinfo,1,{is_number=true}) end
        self.colinfo=rs.colinfo
    end

    local lines = 1
    rs[0]=headind
    local cnt=0
    --run statement
    if grid.col_wrap==nil then print(debug.traceback()) end
    for k,v in ipairs(rs) do
        rs._org[k]=v
        if k>grid.maxcol then break end
        local csize,v1 =0,v
        if not colsize[k] then colsize[k] = {0,1} end
        if self.include_head then
            v=event.callback("ON_COLUMN_VALUE",{#result>0 and result[1][k] or v,v,#result})[2]
        end

        if headind>0 and (type(v) == "number"  or self.include_head and self.colinfo and self.colinfo[k] and self.colinfo[k].is_number) then
            v1=tonumber(v)
            if v1 then
                if grid.digits<38  then
                    v1=math.round(v1,grid.digits)
                    v=v1
                end
                if grid.sep4k=="on" then
                    if v1~=math.floor(v1) then
                        v1=string.format_number("%,.2f",v1,'double')
                    else
                        v1=string.format_number("%,d",v1,'long')
                    end
                    v=v1
                end
            end
            if tostring(v):find('e',1,true) then v=string.format('%99.38f',v):gsub(' ',''):gsub('%.?0+$','') end
            csize = #tostring(v)
        elseif type(v) ~= "string" or v=="" then
            v = tostring(v)  or ""
            csize = #v
        else
            if headind==0 then
                v=v:gsub("([^|]+)|([^|]+)",function(a,b)
                    a,b=a:trim(' '),b:trim(' ')
                    local len1,len2=a:len(),b:len()
                    local max_len=math.max(len1,len2)
                    return ('%s%s\n%s%s'):format(
                        string.rep(' ',math.ceil((max_len-len1)/2)),a,
                        string.rep(' ',math.ceil((max_len-len2)/2)),b)
                end)
            end
            if grid.col_wrap>0 and not v:find("\n") and #v>grid.col_wrap then
                local v1={}
                while v and v~="" do
                    table.insert(v1,v:sub(1,grid.col_wrap))
                    v=v:sub(grid.col_wrap+1)
                end
                v=table.concat(v1,'\n')
            end
            local grp={}
            v=v:convert_ansi()
            v=v:gsub('\192\128',''):gsub('%z','')
            if headind>0 then v=v:gsub("[%s ]+$",""):gsub("[ \t]+[\n\r]","\n"):gsub("\t",'    ') end

            --if the column value has multiple lines, then split lines into table
            for p in v:gmatch('([^\n\r]+)') do
                grp[#grp+1]=p
                --deal with unicode chars
                local l, len = p:strip_ansi(p):ulen()
                if l~=len then self.use_jwriter=true end
                if csize < len then csize=len end
            end
            if #grp > 1 then v=grp end
            if lines < #grp then lines = #grp end
            if headind>0 then
                colsize[k][2] = -1
            end
        end


        if headind==0 and title_style~="none" then
            v=grid.format_title(v)
        end
        rs[k]=v

        if grid.pivot==0 and headind==1 and colbase=="body" and self.include_head then colsize[k][1]=1 end
        if (grid.pivot~=0 or colbase~="head" or not self.include_head or headind==0)
            and colsize[k][1] < csize
        then
            colsize[k][1] = csize
        end
    end

    if lines == 1 then result[#result+1]=rs
    else
        for i=1,lines,1 do
            local r=table.new(#rs,2)
            r[0]=rs[0]
            r._org=rs._org
            for k,v in ipairs(rs) do
                r[k]= (type(v) == "table" and (v[i] or "")) or (i==1 and v or "")
            end
            result[#result+1]=r
        end
    end
    self.headind=headind+1
    return result
end

function grid:add_calc_ratio(column,adjust)
    adjust=tonumber(adjust) or 1
    if not self.ratio_cols then self.ratio_cols={} end
    if type(column)=="string" then
        if not self.include_head then return end
        local head=self.data[1]
        if not head then return end
        for k,v in pairs(head) do
            if tostring(v):upper()==column:upper() then
                self.ratio_cols[k]=adjust
            end
        end
    elseif type(column)=="number" then
        self.ratio_cols[column]=adjust
    end
end

function grid:wellform(col_del,row_del)
    local result,colsize=self.data,self.colsize
    local rownum=grid.row_num
    local siz,rows=#result,table.new(#self.data+1,0)
    if siz==0 then return rows end
    local fmt=""
    local title_dels,row_dels={},""
    col_del=col_del or grid.col_del
    row_del=(row_del or grid.row_del):sub(1,1)
    local pivot=grid.pivot
    local indx=rownum=="on" and 1 or 0
    fmt=col_del:gsub("^%s+","")
    row_dels=fmt
    local format_func=grid.fmt

    if type(self.ratio_cols)=="table" and grid.pivot==0 then
        local keys={}
        for k,v in pairs(self.ratio_cols) do
            keys[#keys+1]=k
        end
        table.sort(keys)
        local rows=self.data
        
        for c=#keys,1,-1 do
            local sum,idx=0,keys[c]
            for _,row in ipairs(rows) do
                sum=sum+(toNum(row._org[idx]) or 0)
            end
            for i,row in ipairs(rows) do
                local n=" "
                if row[0]==0 and i==1 then
                    n="<-Ratio"
                elseif sum>0 then
                    n=toNum(row._org[idx])
                    if n~=nil then
                        n=string.format("%5.2f%%",100*n/sum*self.ratio_cols[idx])
                    else
                        n=" "
                    end
                end
                table.insert(row,idx+1,n)
                --print(table.dump(row))
            end
            table.insert(colsize,idx+1,{7,1})
        end
        self.ratio_cols=nil
    end

    --Generate row formatter
    local color=env.ansi.get_color
    local nor,hor,hl=color("NOR"),color("HEADCOLOR"),color("GREPCOLOR")
    local head_fmt=fmt
    for k,v in ipairs(colsize) do
        local siz=v[1]
        local del=" "
        if pivot==0 or k~=1+indx and (pivot~=1 or k~=3+indx) then del=col_del end
        if k==#colsize then del=del:gsub("%s+$","") end
        fmt=fmt.."%"..(siz*v[2]).."s"..del
        head_fmt=head_fmt..hor.."%"..(siz*v[2]).."s"..nor..del
        table.insert(title_dels, string.rep(result[1][k]~="" and grid.title_del or " ",siz))
        if row_del~="" then
            row_dels=row_dels..row_del:rep(siz)..del
        end
    end

    linesize=self.linesize
    if linesize<=10 then linesize=getWidth(console) end
    linesize=linesize-#env.space-1

    local cut=self.cut
    if row_del~="" then
        row_dels=row_dels:gsub("%s",row_del)
        table.insert(rows,cut(self,row_dels:gsub("[^%"..row_del.."]",row_del)))
    end

    local len=#result
    for k,v in ipairs(result) do
        local filter_flag,match_flag=1,0
        while #v<#colsize do table.insert(v,"") end
        env.event.callback("ON_PRINT_GRID_ROW",v,len)
        --adjust the title style(middle)
        if v[0]==0 then
            for col,value in ipairs(v) do
                local pad=colsize[col][1]-#value
                if pad>=2 then
                    if colsize[col][1]<=40 or pad==2 then
                        v[col]=v[col]:cpad(colsize[col][1])
                    elseif colsize[col][1]<=60 then
                        v[col]=' '..v[col]
                    end
                end
            end
        end
        local row=cut(self,v,format_func,v[0]==0 and head_fmt or fmt)

        if v[0]==0 then
            row=row..nor
        elseif env.printer.grep_text then
            row,match_flag=row:gsub(env.printer.grep_text,hl.."%0"..nor)
            if (match_flag ==0 and not env.printer.grep_dir) or (match_flag>0 and env.printer.grep_dir) then filter_flag=0  end
        end
        if filter_flag==1 then table.insert(rows,row) end
        if not result[k+1] or result[k+1][0]~=v[0] then
            if #row_del==1 and filter_flag==1 and v[0]~=0 then
                table.insert(rows,cut(self,row_dels))
            elseif v[0]==0 then
                table.insert(rows,cut(self,title_dels,format_func,fmt))
            end
        end
    end

    if result[#result][0]>0 and (row_del or "")=="" and (col_del or ""):trim()~="" then
        local line=cut(self,title_dels,format_func,fmt)
        line=line:gsub(" ",grid.title_del):gsub(col_del:trim(),function(a) return ('+'):rep(#a) end)
        table.insert(rows,line)
        table.insert(rows,1,line)
    end
    self=nil
    return rows
end

function grid.print(rows,include_head,col_del,row_del,psize,prefix,suffix)
    psize=psize or 10000
    local str=prefix and (prefix.."\n") or ""
    local test
    if include_head=='test' then test,include_head=true,nil end
    if rows.__class then
        include_head=rows.include_head
        rows=rows:wellform(col_del,row_del)
        str=str..table.concat(rows,"\n",1,math.min(#rows,psize+2));
    else
        include_head=grid.new(include_head).include_head
        str=str..grid.tostring(rows,include_head,col_del,row_del,psize)
    end
    if grid.bypassemptyrs=='on' and #rows<(include_head and 3 or 1) then return end
    if test then env.write_cache("grid_output.txt",str) end
    print(str,'__BYPASS_GREP__')
    if suffix then print(suffix) end
end

function grid.onload()
    local set=env.set.init
    grid.params={}
    for k,v in pairs(params) do
        grid[v.name]=v.default
        if type(k)=="table" then
            for _,k1 in ipairs(k) do grid.params[k1]=v end
        else
            grid.params[k]=v
        end
        set(k,grid[v.name],grid.set_param,"grid",v.desc,v.range)
    end
    env.ansi.define_color("HEADCOLOR","BRED;HIW","ansi.grid","Define grid title's color, type 'ansi' for more available options")
end

return grid