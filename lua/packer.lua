--The packerryption function is someway useless, however you may feel better by comparing to plain text :)

local string=string
local packer={}

local function rechar(str,offset)
    local byte=string.byte(str)
    return     string.char(byte+offset<128 and byte+offset or byte)
end

function packer.pack(func)
    local str=string.dump(func)
    local obj={}
    for i=1,#str,2 do
        obj[#obj+1]=rechar(str:sub(i,i),1)
    end
    for i=2,#str,2 do
        obj[#obj+1]=rechar(str:sub(i,i),1)
    end
    return "FUNC:"..table.concat(obj,"")
end

function packer.unpack(str)
    
    if not str or str:sub(1,5)~= "FUNC:" then
        return str
    end
    str=str:sub(6)
    local half=math.ceil(#str/2)
    local obj={}
    for i=1,half,1 do
        obj[#obj+1]=rechar(str:sub(i,i),-1)
        if half+i<=#str then
            obj[#obj+1]=rechar(str:sub(i+half,i+half),-1)
        end
    end
    
    str=loadstring(table.concat(obj,""))
    if str==nil then
        local b=obj[5]:byte()
        obj[5]=string.char(b==0 and 8 or b==8 and 0 or b)
        str=loadstring(table.concat(obj,""))
    end
    return str
end

function packer.pack_str(str)
    if not str or str:sub(1,5)== "FUNC:" then
        return str
    end
    local func=loadstring("return function() local tmp=[["..tostring({}).."]];return [["..str.."]] end")()
    return packer.pack(func)
end

function packer.unpack_str(str)
    while true do
        str=packer.unpack(str)
        if type(str)=="function" then 
            str=str() 
        else 
            break
        end
    end
    return str
end

return packer

