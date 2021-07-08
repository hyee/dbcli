/*[[Show active sessions]]*/
ENV AUTOHIDE COL

col current_memory,trx_latency justify right

select * from sys.processlist where state is not null