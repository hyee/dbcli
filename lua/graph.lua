local env=env
local json,math,graph,cfg=env.json,env.math,env.class(env.scripter),env.set
local template,cr
--Please refer to http://dygraphs.com/options.html for the graph options that used in .chart files

function graph:ctor()
    self.command='graph'
    self.ext_name='chart'
    if not template then
        template=env.load_data(env.WORK_DIR.."lib"..env.PATH_DEL.."dygraphs.html",false)
        env.checkerr(type(template)=="string",'Cannot load file "dygraphs.html" in folder "lib"!')
        cr=[[
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
        <br/>]]
        --template=template:gsub('@GRAPH_FIELDS',cr)
    end
    cfg.init("ChartSeries",12,set_param,"core","Number of top series to be show in graph chart(see command 'chart')",'1-500')
end


function graph:run_script(cmd,...)
    local args,print_args,context,rs,file={...},false
    local units={}
    context,args,print_args,file=self:get_script(cmd,args,print_args)
    if not args or cmd:sub(1,1)=='-' then return end
    context=loadstring(('return '..context):gsub(self.comment,"",1))
    if not context then
       return print("Invalid syntax in "..file)
    end
    context=context()
    env.checkerr(type(context)=="table" and type(context._sql)=="string","Invalid definition, should be a table with '_sql' property!")
    local default_attrs={
            --legend='always',
            labelsDivStyles= {border='1px solid black',width=80},
            rollPeriod=8,
            showRoller=true,
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
    local title,txt,keys,values,collist,temp=string.char(0x1),{},{},{},{},{}
    local counter=-1
    local function getnum(val)
        if not val then return 0 end
        if type(val)=="number" then return val end
        return tonumber(val:match('[eE%.%-%d]+')) or 0
    end
    while true do
        local row=self.db.resultset:fetch(rs,self.db.conn)
        if not row then break end
        counter=counter+1
        --For pivot, col1=x-value, col2=Pivot,col3=y-value
        if pivot then
            local x,p,y=row[1],row[2],{table.unpack(row,3)}
            if #keys==0 then
                units={table.unpack(row,3)}
                keys[1],values[title]=title,{x}
                env.checkerr(#units>0,'Pivot mode should have at least 3 columns!')
                print('Start fetching data into HTML file...')
            else
                if not collist[p] then
                    values[title][#values[title]+1],temp[#temp+1]=p,{}
                    collist[p]={#values[title],0,0}
                end
                if not values[x] then
                    values[x]={x,table.unpack(temp)}
                    keys[#keys+1]=x
                end
                values[x][collist[p][1]]=y
                local val=getnum(y[1])
                collist[p][2]=collist[p][2]+val
                if y[1] and y[1]~="" then
                    collist[p][3]=collist[p][3]+1
                    collist[p][4],collist[p][5]=math.min(val,collist[p][4] or val),math.max(val,collist[p][5] or val)
                end
            end
        else
            if not values[title] then values[title]=row end
            for i=2,#row do
                if #txt==0 then
                    collist[row[i]]={i,0,0}
                else
                    local col,val=collist[values[title][i]],getnum(row[i])
                    col[2]=col[2]+val
                    if row[i] and row[i]~="" and val then
                        col[3],col[4],col[5]=col[3]+1,math.min(val,col[4] or val),math.max(val,col[5] or val)
                    end
                    if not row[i] then row[i]=0 end
                end
            end
            txt[#txt+1]=table.concat(row,',')
        end
    end

    env.checkerr(counter>2,"No data found for the given criteria!")
    print(string.format("%d rows processed.",counter))

    --Print summary report
    local sorter={table.unpack(values[title],2)}
    table.sort(sorter,function(a,b)
        if collist[a][2]==collist[b][2] then return a<b end
        return collist[a][2]>collist[b][2]
    end)

    for k,v in pairs(context) do
        default_attrs[k]=v
    end
    local content,ylabels,default_ylabel = template,default_attrs._ylabels or {},default_attrs.ylabel
    local output=env.grid.new()
    output:add{"Item","Total "..(ylabels[1] or default_attrs.ylabel or ""),'|',"Rows","Appear",'%',"Min","Average","Max"}

    for k,v in pairs(collist) do
        if v[2] then
            output:add{ k,math.round(v[2],2),'|',
                        v[3],math.round(v[3]*100/(counter-1),2),'|',
                        v[4],math.round(v[2]/v[3],2),v[5]}
        else
            output:add{k,0,'|',0,0,'|',0,0,0}
        end
    end

    output:add_calc_ratio(2)
    output:sort(2,true)
    output:print(true)
    --Generate graph data
    self.dataindex,self.data=0,{}
    if pivot then
        --Sort the columns by sum(value)
        local max_series=math.min(#sorter,cfg.get('ChartSeries'))
        for idx=1,#units do
            local txt={}
            for k,v in ipairs(keys) do
                local row={values[v][1],table.unpack(temp,1,max_series)}
                for i=1,max_series do
                    local col=values[v][collist[sorter[i]][1]]
                    row[i+1]=k==1 and col or col and col[idx] or 0
                end
                txt[k]=table.concat(row,',')
            end
            self.dataindex=self.dataindex+1
            self.data[self.dataindex]=table.concat(txt,'\n')
        end
    else
        self.dataindex=self.dataindex+1
        self.data[self.dataindex]=table.concat(txt,'\n')
    end

    local replaces={
        ['@GRAPH_TITLE']=default_attrs.title
    }

    for k,v in pairs(default_attrs) do
        if k:sub(1,1)=='_' then
            default_attrs[k]=nil
        end
    end

    for i=1,self.dataindex do
        replaces['@GRAPH_INDEX']=i
        if i>1 then default_attrs.title="" end
        default_attrs.ylabel=ylabels[i] or default_ylabel or units[i]
        local attr=json.encode(default_attrs)
        local graph_unit=cr:replace('@GRAPH_ATTRIBUTES',attr,true)
        for k,v in pairs(replaces) do
            graph_unit=graph_unit:replace(k,v,true)
            if i==1 then
                content=content:replace(k,v,true)
            end
        end
        graph_unit=graph_unit:replace('@GRAPH_DATA',self.data[i],true)
        content=content..graph_unit
    end
    content=content.."</body></html>"
    local file=env.write_cache(cmd.."_"..os.date('%Y%m%d%H%M%S')..".html",content)
    print("Result written to "..file)
    os.shell(file)
end

local function set_param(name,value)
    return tonumber(value)
end

function graph:__onload()

end

return graph