local result = obj.redirect('table_partition')
for k, sql in env.ipairs(result) do
    result[k] = sql:gsub('[Aa][Ll][Ll]_[Pp][Aa][Rr][Tt]_[Ii][Nn][Dd][Ee][Xx][Ee][Ss]','ALL_PART_INDEXES')
              :gsub('(%W)[Pp][Aa][Rr][Tt]','%1SUBPART'):gsub('SUBPART_INDEXES','PART_INDEXES')
end
return result
