local env,java=env,env.java
local locale={}

function locale.init()
	locale.locale=java.require("java.util.Locale")
	for k,v in java.fields(locale.locale) do		
		if type(k) == "string" and k:upper()==k then
			locale[v]=locale[k]
		end
	end
	print(locale.locale:getDefault():getDisplayName() )

	--locale.locale:setDefault("ENGLISH")
end

function locale.get()

end

function locale.set(param)

end

function locale.setEncode(encode)

end

locale.init()
locale.set("ENGLISH")

return locale;