local env,table=env,table
local json,math,graph,cfg=env.json,env.math,env.class(env.scripter),env.set
local template,cr
--[[
    Please refer to "http://dygraphs.com/options.html" for the graph options that used in .chart files.
    More examples can be found in folder "oracle\chart" 
    The content of .chart file must follow the lua table syntax. for example: {a=..,b={...}}
        and it contains at least one attribute "_sql" which returns <date>+<name>+<value(s)> fields
    Settings:
        set ChartSeries <number>: Define the max series to be shown in the chart.
                                  If the data contains many series, only show the top <number> deviations
    Common options from dygraphs(available values are all true/false):
        ylabel,title,height,rollPeriod,drawPoints,logscale,fillGraph,stackedGraph,
        stepPlot,strokePattern,plotter
    Other options:
        _attrs="<sql_statement>" : Select statement to proceduce the attributes, 
                                   field name matches the attribute name,
                                   and must return only one row, the output fields can also can be used as a variable inside "_sql" option
                                   i.e.:In below case, the chart title is defined as 'THIS IS TITLE', and &title, &group by variables can be used. 
                                       _attrs="select 'THIS IS TITLE' title, 'event_name' group_by from dual"
        _sql  ="<sql_statement>" : The select statement to produce the graph data
                                   The "_pivot" attribute impacts the SQL output:
                                       _pivot=false:
                                            X-label    = 1st field values, mainly be a time value
                                            Asis Name  = 2nd+ field names
                                            Asis Value = 2nd+ field values(number)
                                            2nd+ fields: field name as the curve name and value as the Y-Asis
                                            Example:
                                               date(x-label)  latch1  latch2
                                               --------------------------------
                                               2015-1-1        99      98
                                               2015-1-1        97      96
                                       _pivot=true:
                                            X-label    = 1st field values, mainly be a time value
                                            Axis Name  = 2nd field value(string)
                                            Axis Value = 3rd+ values(number), if colums(N)>3, then create N-2 charts 
                                            Example:
                                               date(x-label)  name   Y1  Y2 
                                               -----------------------------
                                               2015-1-1      latch1  99  24 
                                               2015-1-1      latch2  98  23 
                                                                        ||(split into)
                                                                        \/
                                               date(Y1) latch1  latch2      date(Y2)  latch1  latch2
                                               ------------------------- + ------------------------
                                               2015-1-1  99      98         2015-1-1   24      23  
                                               
                                       _pivot="mixed":
                                            X-label    = 1st field values, mainly be a time value
                                            Axis Name  = <2nd field value(string)> + <3rd+ field name>
                                            Axis Value = 3rd+ values
                                            Example:
                                               date(x-label)  name   Y1  Y2
                                               ----------------------------
                                               2015-1-1      latch1  99  24
                                               2015-1-1      latch2  98  23 
                                                         ||(convert into)
                                                         \/
                                               date(x-label)  latch1[Y1] latch1[Y2] latch2[Y1] latch2[Y2]
                                               ----------------------------------------------------------
                                               2015-1-1        99         24        98          23
                                            Refer to "racping.chart" for more example
                                   Special column names: Special column names will not be shown in the report
                                       RNK_: If the output contains the "RNK_" field, then only proceduce the top 30 RNK_ data. Refer to "ash.chart" for example
                                       RND_: If the output contains both "RNK_" and "RND_", then will not produce the top 30 RNK_ data
                                       |   : To be developed
                                       none-alphanumeric: If the column name is all none-alphanumeric chars or is "", then will not include into the chart report. for example, '*','&%'
        _pivot=true|false|"mixed": indicate if pivot the >2nd numberic fields, refer to above
        _ylabels={"<label1>",...}: Customize the ylabel for each chart, not not define then use the names from "_sql"
        _range="<Time range>"    : Used in sub-title, if not specified then auto-caculate the range
        _sorter=<number>         : Choose the top <ChartSeries> based on the nth field of the summary, default as deviation%(12)
        deviation=true|false     : False for org value, and true to display the data based on deviation%(value*100/average)
]]--

function graph:ctor()
    self.command='graph'
    self.ext_name='chart'
    self.ext_command={"graph","gr"}
end

function graph:rehash(script_dir,ext_name,extend_dirs)
    template=nil
    return env.scripter.rehash(self,script_dir,ext_name,extend_dirs)
end


function graph:run_sql(sql,args,cmd,file)
    if type(sql)=="table" and not sql._sql then
        for i=1,#sql do self:run_sql(sql[i],args[i],cmd[i],file[i]) end
        return
    end

    if not template then
        template=env.load_data(env.WORK_DIR.."lib"..env.PATH_DEL.."dygraphs.html",false)
        env.checkerr(type(template)=="string",'Cannot load file "dygraphs.html" in folder "lib"!')
        cr=[[<textarea id="divNoshow@GRAPH_INDEX" style="white-space: nowrap;width:100%;height:300px;display:none">@GRAPH_DATA</textarea>
        <script type="text/javascript">
        write_options(@GRAPH_INDEX);
        var g@GRAPH_INDEX=new Dygraph(
            document.getElementById("divShow@GRAPH_INDEX"),
            function() {return document.getElementById("divNoshow@GRAPH_INDEX").value;},
            @GRAPH_ATTRIBUTES
        );
        g@GRAPH_INDEX.ready(function() {sync_options(@GRAPH_INDEX);});
        </script>
        <hr/><br/><br/>]]
        --template=template:gsub('@GRAPH_FIELDS',cr)
    end

    local charts,rs,rows={}
    
    local context,err=sql
    if type(sql)=='string' then 
        context,err=loadstring(('return '..sql):gsub(self.comment,"",1))
        env.checkerr(context,"Error when loading file %s: %s",file,err)
        context=context()
    end
    
    env.checkerr(type(context)=="table" and type(context._sql)=="string","Invalid definition, should be a table with '_sql' property!")
    local default_attrs={
            --legend='always',
            labelsDivStyles= {border='1px solid black',width=80},
            rollPeriod=8,
            showRoller=false,
            height= 400,
            includeZero=true,
            axisLabelFontSize=12,
            labelsSeparateLines=true,
            animatedZooms=true,
            highlightSeriesOpts= {
              strokeWidth= 2,
              strokeBorderWidth=2,
              highlightCircleSize=2,
            },
        }
    if context._attrs then
        rs=self.db:exec(context._attrs,args)
        rows=self.db.resultset:rows(rs,1)
        local title=rows[1]
        local value=rows[2]
        env.checkerr(value,context._error or 'No data found for the given criteria!')
        for k,v in ipairs(title) do
            if not v:find('[a-z]') then v=v:lower() end
            args[v]=value[k]
            --deal with table
            if value[k] and value[k]:sub(1,1)=='{' then value[k]=json.decode(value[k]) end
            default_attrs[v]=value[k]
        end
    end

    if default_attrs.title then
        print("Running Report ==> "..default_attrs.title..'...')
    end

    local sql,pivot=context._sql,context._pivot
    --Only proceduce top 30 curves to improve the performance in case of there is 'RNK_' field
    if sql:match('%WRNK_%W') and not sql:find('%WRND_%W') then
        sql='SELECT * FROM (SELECT /*+NO_NOMERGE(A)*/ A.*,dense_rank() over(order by RNK_ desc) RND_ FROM (\n'..sql..'\n) A) WHERE RND_<=30 ORDER BY 1,2'
    end

    rs=self.db:exec(sql,args)
    local title,csv,xlabels,values,collist,temp=string.char(0x1),{},{},table.new(10,255),{},{}
    
    local function getnum(val)
        if not val then return 0 end
        if type(val)=="number" then return val end
        return tonumber(val:match('[eE%.%-%d]+')) or 0
    end

    local function is_visible(title)
        return not (title=="RNK_" or title=="RND_" or title=="HIDDEN_" or title:match('^%W*$')) and true or false
    end

    local counter,range_begin,range_end=-1
    rows=self.db.resultset:rows(rs,-1)
    local head,cols=table.remove(rows,1)
    local maxaxis=cfg.get('ChartSeries')
    table.sort(rows,function(a,b) return a[1]<b[1] end)
    --print(table.dump(rows))
    if pivot==nil then
        for i=2,6 do
            local row=rows[i]
            if not row then break end
            local cell=row[2]
            if cell and cell~="" then
                if type(cell)=="number" then
                    pivot=false
                elseif type(cell)~="string" or not cell:match('%d+') then 
                    pivot=true
                    break
                elseif pivot==nil then
                    pivot=false
                end
            end
        end
    end

    if pivot=="mixed" then
        local data={}
        for k,v in ipairs(rows) do
            for i=3,#v do
                if is_visible(head[i]) then
                    data[#data+1]={v[1],v[2].."["..head[i]..']',v[i]}
                end
            end
        end
        table.insert(data,1,{head[1],head[2],"Value"})
        pivot,rows,head=true,data,data[1]
    else
        table.insert(rows,1,head)
    end

    local start_value=pivot and 3 or 2

    head,cols={},0
    while true do
        counter=counter+1
        local row=rows[counter+1]
        if not row then break end
        if counter==0 then
            for i=1,#row do
                local cell=is_visible(row[i])
                head[#head+1],head[row[i]],cols=row[i],cell,cols+(cell and 1 or 0)
            end
        end

        for i=#head,1,-1 do if not head[head[i]] then table.remove(row,i) end end

        for i=1,cols do
            if row[i]==nil or row[i]=='' then 
                row[i]=''
            elseif (counter==0 or i<start_value) then
                row[i]=tostring(row[i]):gsub(",",".")
            elseif counter>0 and i>=start_value and type(row[i])~="number" and not tostring(row[i]):match('^%d') then
                env.raise("Invalid number at row #%d field #%d '%s', row information: %s",counter,i,row[i],table.concat(row,','))
            end 
        end

        if counter>0 and row[1]~="" then
            local x=row[1]
            if not range_begin then
                if tonumber(x) then
                    range_begin,range_end=9E9,0
                else
                    range_begin,range_end='ZZZZ','0'
                end
            end
            if type(range_begin)=="number" then x=tonumber(x) end
            range_begin,range_end=range_begin>x and x or range_begin, range_end<x and x or range_end
        end
        --For pivot, col1=label, col2=Pivot,col3=y-value
        --collist: {label={1:nth-axis,2:count,3:1st-min,4:1st-max,5+:sum(value)-of-each-chart},...}
        if pivot then
            local x,label,y=row[1],row[2],{table.unpack(row,3)}
            
            if #xlabels==0 then
                charts,xlabels[1],values[title]=y,title,table.new(#rows+10,5)
                values[tile][1]=x
                env.checkerr(#charts>0,'Pivot mode should have at least 3 columns!')
                print('Fetching data into HTML file...')
            else
                if not collist[label] then
                    values[title][#values[title]+1],temp[#temp+1]=label,0
                    collist[label]={#values[title],0,data={}}
                end
                local col=collist[label]
                if not values[x] then
                    values[x]={x,table.unpack(temp)}
                    xlabels[#xlabels+1]=x
                end
                values[x][col[1]]=y
                local val=getnum(y[1])
                if counter>0 then
                    col[2],col.data[#col.data+1]=col[2]+1,val
                    col[3],col[4]=math.min(val,col[3] or val),math.max(val,col[4] or val)
                end
                for i=1,#y do
                    col[4+i]=(col[4+i] or 0)+getnum(y[i])
                end 
            end
        else
            local c=math.min(#row,maxaxis+1)
            row={table.unpack(row,1,c)}
            if not values[title] then values[title]=row end
            csv[#csv+1]=table.concat(row,',')
            for i=2,c do
                if counter==0 then
                    collist[row[i]]={i,0,data={}}
                    --row[i]='"'..row[i]:gsub('"','""')..'"' --quote title fields
                else
                    local col,val=collist[values[title][i]],getnum(row[i])
                    if counter>0 then
                        col[2],col[5],col.data[#col.data+1]=col[2]+1,(col[5] or 0)+val,val
                        col[3],col[4]=math.min(val,col[3] or val),math.max(val,col[4] or val)
                    end
                end
            end
            
        end
    end

    env.checkerr(counter>2,"No data found for the given criteria!")
    print(string.format("%d rows processed.",counter))

    --Print summary report
    local labels={table.unpack(values[title],2)}
    table.sort(labels,function(a,b)
        if collist[a][2]==collist[b][2] then return a<b end
        return collist[a][2]>collist[b][2]
    end)

    for k,v in pairs(context) do
        default_attrs[k]=v
    end
    local content,ylabels,default_ylabel = template,default_attrs._ylabels or {},default_attrs.ylabel
    local output=env.grid.new()
    output:add{"Item","Total "..(ylabels[1] or default_attrs.ylabel or ""),'|',"Rows","Appear",'%',"Min","Average","Max","Std Deviation","Deviation(%)"}

    for k,v in pairs(collist) do
        if v[5] and v[5]>0 then
            local avg,stddev=v[5]/v[2],0;
            for _,o in ipairs(v.data) do
                stddev=stddev+(o-avg)^2/v[2]
            end
            v.data,stddev=nil,stddev^0.5
            output:add{ k,math.round(v[5],2),'|',
                        v[2],math.round(v[2]*100/counter,2),'|',
                        math.round(v[3],5),math.round(avg,3),math.round(v[4],5),
                        math.round(stddev,3),math.round(100*stddev/avg,3)}
        else
            output:add{k,0,'|',0,0,'|',0,0,0,0,0}
        end
    end

    output:add_calc_ratio(2)
    output:sort(tonumber(default_attrs._sorter) or #output.data[1],true)
    output:print(true)
    local data,axises,temp=output.data,{},{}
    table.remove(data,1)
    for i=#data,math.max(1,#data-maxaxis+1),-1 do
        axises[#axises+1],temp[#temp+1]=data[i][1],""
    end
    --Generate graph data
    self.dataindex,self.data=0,{}
    
    if pivot then
        --Sort the columns by sum(value)
        for idx=1,#charts do
            local csv,avgs={},{}
            for rownum,xlabel in ipairs(xlabels) do
                local row={values[xlabel][1],table.unpack(temp)}
                for i=1,#axises do
                    local col=collist[axises[i]]
                    local cell=values[xlabel][col[1]]
                    avgs[i],avgs[axises[i]]=axises[i],col[4+idx]/col[2]
                    row[i+1]=type(cell)=="table" and cell[idx] or cell or 0
                    --if rownum==1 then row[i+1]='"'..row[i+1]:gsub('"','""')..'"' end --The titles
                end
                csv[rownum]=table.concat(row,',')
            end
            self.dataindex=self.dataindex+1
            self.data[self.dataindex]={table.concat(csv,'\n'),avgs}
        end
    else
        local avgs={}
        for k,v in pairs(collist) do
            avgs[#avgs+1],avgs[k]=k,v[5]/v[2]
        end
        self.dataindex=self.dataindex+1
        self.data[self.dataindex]={table.concat(csv,'\n'),avgs}
    end

    local replaces={
        ['@GRAPH_TITLE']=default_attrs.title or "",
        ['@TIME_RANGE']=default_attrs._range or ('(Range:  '..tostring(range_begin)..' ~~ '..tostring(range_end)..')')
    }

    for k,v in pairs(default_attrs) do
        if k:sub(1,1)=='_' then
            default_attrs[k]=nil
        end
    end

    default_attrs.title=nil

    for i=1,self.dataindex do
        replaces['@GRAPH_INDEX']=i
        default_attrs.ylabel=ylabels[i] or default_ylabel or charts[i]
        default_attrs._avgs=self.data[i][2]
        if default_attrs.ylabel then
            default_attrs.title="Unit: "..default_attrs.ylabel
        end
        local attr=json.encode(default_attrs)
        local graph_unit=cr:replace('@GRAPH_ATTRIBUTES',attr,true)
        for k,v in pairs(replaces) do
            graph_unit=graph_unit:replace(k,v,true)
            if i==1 then
                content=content:replace(k,v,true)
            end
        end
        graph_unit=graph_unit:replace('@GRAPH_DATA','\n'..self.data[i][1]..'\n',true)
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

function graph:run_stmt(option,sql)
    env.checkhelp(option)
    local fmt={}
    if option:sub(1,1)=='-' then
        option=option:sub(2):lower()
        if option~='y' and option~='n' and option~='m' then env.checkhelp(nil) end
        fmt._pivot=option=='y' and true or option=='m' and 'mixed'
        if option=='n' then fmt._pivot=false end
    else
        sql=option
    end
    fmt._sql=sql
    return self:run_sql(fmt,{},'last_chart')
end

function graph:__onload()
    local help=[[
    Generate graph chart regarding to the input SQL. Usage: @@NAME [-n|-p|-m] <Select statement>
    Options:
        -y: the output fields are "<date> <label> <values...>"
        -n: the output fields are "date <label-1-value> ... <label-n-value>"
        -m: mix mode,  the output fields are "<date> <label> <sub-label values...>"
    If not specify the option, will auto determine the layout based on the outputs.]]
    env.set_command(self,self.ext_command, help,self.run_stmt,'__SMART_PARSE__',3)
    cfg.init("ChartSeries",15,set_param,"core","Number of top series to be show in graph chart(see command 'chart')",'1-30')
end

return graph