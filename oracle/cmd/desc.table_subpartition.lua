local result=obj.redirect('table_partition')
for k,sql in env.ipairs(result) do
    result[k]=sql:gsub('part','subpart')
end
return result