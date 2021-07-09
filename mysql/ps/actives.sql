/*[[Show active sessions]]*/
ENV AUTOHIDE COL FEED OFF

col current_memory,trx_latency justify right
print sys.processlist
print ===============
select * from sys.processlist where command!='Sleep';

print performance_schema.threads
print ===============
select * from performance_schema.threads where processlist_state is not null;