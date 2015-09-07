local rawget,rawset,setmetatable=rawget,rawset,setmetatable

local function newindex(self,k,v)
    if type(v)=="function" then
        if k=="onload" or k=="onunload" or k=="__onload" or k=="__onunload" then
            local super=self.super or self.__super
            local k1='__'..k:match("(%w+)$")
            if  type(super)=="table" and type(super[k1])=="function" then
                local v1=v
                v=function(...) super[k1](...);v1(...) end
            end
        end
    end
    rawset(self,k,v)
end

function class(super,init)
    local this_class=setmetatable(init or {},{__newindex=newindex})
    super=super and rawget(super,'__class') or super
    this_class.__className=debug.getinfo(2).short_src
    this_class.new=function(...) 
        local obj={}
        local attrs,super

        obj.__class=this_class

        if this_class.__super then
            super,attrs = this_class.__super.new(...)      
        else
            super,attrs={},{}
        end
        rawset(obj,'super',super)

        attrs.__instance=obj

        for k,v in pairs(this_class) do
            if type(v)=="function" then rawset(obj,k,v) end
            rawset(attrs,k,v)
        end

        setmetatable(obj,{
            __index=attrs,
            __newindex=function(self,k,v)
                 if type(v)=="function" then
                    newindex(self,k,v)
                    v=rawget(self,k)
                 end

                 if type(v)~="function" or rawget(attrs,k)==nil then
                    rawset(attrs,k,v)
                 end                
            end
        })

        local create=rawget(this_class,'ctor')
        if type(create)=="function" then create(obj,...) end

        for _,k in ipairs({'onload','onunload'}) do
            if not obj[k] then obj[k]=obj['__'..k] end
        end

        return obj,attrs
    end

    if type(super)=="table" and type(super.new)=="function" then    
        rawset(this_class,'__super',super)
    end
    
    return this_class
end

return class