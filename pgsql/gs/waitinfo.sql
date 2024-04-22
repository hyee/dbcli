/*[[List available wait info from get_wait_event_info(). Usage: @@NAME <keyword>]]*/
SELECT * 
FROM   get_wait_event_info() a
WHERE  lower(concat(module,'/',"type",'/',event)) like '%&V1%'; 