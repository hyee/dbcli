local env=env
local json,graph=env.json,env.class(env.scripter)
local template,cr
--Please refer to http://dygraphs.com/options.html for the graph options that used in .chart files

function graph:ctor()
    self.command='graph'
    self.ext_name='chart'
    if not template then
        template=env.load_data(env.WORK_DIR.."lib"..env.PATH_DEL.."dygraphs.html",false)
        env.checkerr(type(template)=="string",'Cannot load file "dygraphs.html" in folder "lib"!')
        local cr=[[
        <div id="divNoshow@GRAPH_INDEX" style="display:none">@GRAPH_DATA</div> 
        <div id="divShow@GRAPH_INDEX" style="width:100%;"></div><br/></br> 
        <div id="divLabel@GRAPH_INDEX" style="width:90%; margin-left:5%"></div>
        <script type="text/javascript"> 
        new Dygraph(
            document.getElementById("divShow@GRAPH_INDEX"),
            function() {return document.getElementById("divNoshow@GRAPH_INDEX").innerHTML;},
            @GRAPH_ATTRIBUTES
        );
        </script> 
        ]]
        cr=cr:gsub('%%','%%%%')
        template=template:gsub('@GRAPH_FIELDS',cr)
    end

end

function graph:run_script(cmd,...)
    local args,print_args,context,rs,file={...},false
    context,args,print_args,file=self:get_script(cmd,args,print_args)
    if not args or cmd:sub(1,1)=='-' then return end
    context=loadstring(('return '..context):gsub(self.comment,"",1))
    if not context then
       return print("Invalid syntax in "..file)
    end
    context=context()
    env.checkerr(type(context)=="table" and type(context._sql)=="string","Invalid definition, should be a table with '_sql' property!")
    local default_attrs={
            legend='always',
            labelsDivStyles= {border='1px solid black'},
            rollPeriod=10,
            height= 400,
            highlightSeriesOpts= {
              strokeWidth= 2,
              strokeBorderWidth=2,
              highlightCircleSize=2,
            },
        }
    if context._attrs then
        rs=self.db:exec(context._attrs,args)
        local title=self.db.resultset:fetch(rs,self.db.conn)
        local value=self.db.resultset:fetch(rs,self.db.conn)
        env.checkerr(value,context._error or 'No data found for the given criteria!')
        for k,v in ipairs(title) do
            if not v:find('[a-z]') then v=v:lower() end
            args[v]=value[k]
            --deal with table
            if value[k] and value[k]:sub(1,1)=='{' then value[k]=json.decode(value[k]) end
            default_attrs[v]=value[k]
        end
    end

    local sql,pivot=context._sql,context._pivot
    rs=self.db:exec(sql,args)
    local title,txt,keys,values,list,temp=string.char(0x1),{},{},{},{},{}
    local counter=-1
    while true do
        local row=self.db.resultset:fetch(rs,self.db.conn)
        if not row then break end
        counter=counter+1
        --For pivot, col1=x-value, col2=Pivot,col3=y-value
        if pivot then
            local x,p,y=table.unpack(row)
            env.checkerr(y,'Pivot mode should have 3 columns!')
            if #keys==0 then
                keys[1],values[title]=title,{x}
                print('Start fetching data into HTML file...')
            else
                if not list[p] then
                    values[title][#values[title]+1],temp[#temp+1]=p,""
                    list[p]=#values[title]
                end
                if not values[x] then
                    values[x]={x,table.unpack(temp)}
                    keys[#keys+1]=x
                end
                values[x][list[p]]=y or ""
            end
        else
            txt[#txt+1]=table.concat(row,',')
        end
    end
    print(string.format("%d rows processed.",counter))

    if pivot then
        for k,v in ipairs(keys) do
            txt[k]=table.concat(values[v],',')
        end
    end

    txt=table.concat(txt,'\n')
    local template=template

    for k,v in pairs(context) do
        default_attrs[k]=v
    end

    for k,v in pairs(default_attrs) do
        if k:sub(1,1)=='_' then 
            default_attrs[k]=nil 
        elseif type(v)=="string" then
            default_attrs[k]=default_attrs[k]:gsub('@GRAPH_INDEX',1)
        end
    end

    local replaces={
            ['@GRAPH_INDEX']=1,
            ['@GRAPH_TITLE']=default_attrs.title,
            ['@GRAPH_ATTRIBUTES']=json.encode(default_attrs),
            ['@GRAPH_DATA']=txt,}

    for k,v in pairs(replaces) do
        v=tostring(v):gsub('%%','%%%%')
        template = template:gsub(k,v)
    end
    
    print("Result written to "..env.write_cache(cmd.."_"..os.date('%Y%m%d%H%M%S')..".html",template))
end

function graph:__onload()
    
end


return graph