local result=obj.redirect('table_partition')
for k,sql in env.ipairs(result) do
    result[k]=sql:gsub('(%W)[Pp][Aa][Rr][Tt]','%1SUBPART'):gsub('SUBPART_INDEXES','PART_INDEXES')
end
return result