local rawget,rawset,setmetatable=rawget,rawset,setmetatable

function class(super)
	local this_class={}
	this_class.new=function(...) 
		local obj={}
		local attrs

		obj.__class=this_class

		if this_class.__super then
			obj.super,attrs = this_class.__super.new(...)			
		else
			obj.super,attrs={},{}
		end

		attrs.__instance=obj

		for k,v in pairs(this_class) do
			if type(v)=="function" then
				rawset(obj,k,v)
			end
			rawset(attrs,k,v)
		end

		setmetatable(obj,{
			__index=attrs,
			__newindex=function(self,k,v)
			 	if type(v)=="function" then
			 		rawset(self,k,v)
			 	end

			 	if type(v)~="function" or rawget(attrs,k)==nil then
			 		rawset(attrs,k,v)
			 	end				
			end
		})
		local create=rawget(this_class,'ctor')
		if type(create)=="function" then create(obj,...) end

		return obj,attrs
	end

	if type(super)=="table" and type(super.new)=="function" then	
		this_class.__super=super
		--this_class=setmetatable(this_class,{__index=super})
	end
	
	return this_class
end

return class