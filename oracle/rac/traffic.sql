/*[[Show Rac Traffic Control, refer to Doc ID 1619155.1.
a. Set _lm_sync_timeout to 1200    (this recommendation is valid only for databases that are12.2 and lower) 
    Setting this will prevent some timeouts during reconfiguration and DRM. 
    It's a static parameter and rolling restart is supported.

b. Set shared_pool_size to 15% or larger of the total SGA size.
    For example, if SGA size is 1 TB, the shared pool size should be at least 150 GB. It's a dynamic parameter.

c. Set _gc_policy_minimum to 15000
    There is no need to set _gc_policy_minimum if DRM is disabled by setting _gc_policy_time = 0. 
    _gc_policy_minimum is a dynamic parameter, _gc_policy_time is a static parameter and rolling restart is not supported. 
    To disable DRM, instead of _gc_policy_time, _lm_drm_disable should be used as it's dynamic.
    query select SOPENS+XOPENS+XFERS from table(gv$(cursor(select * from  x$object_policy_statistics)))

d. Set _lm_tickets to 5000    (this recommendation is valid only for databases that are12.2 and lower)
    Default is 1000.   
    Allocating more tickets (used for sending messages) avoids issues where we ran out of tickets during the reconfiguration. 
    It's a static parameter and rolling restart is supported. 
    When increasing the parameter, rolling restart is fine but a cold restart can be necessary when decreasing.

e. Set gcs_server_processes to the twice the default number of lms processes that are allocated.    (this recommendation is valid only for databases that are12.2 and lower)
    The default number of lms processes depends on the number of CPUs/cores that the server has, 
    so please refer to the gcs_server_processes init.ora parameter section in the Oracle Database Reference Guide 
    for the default number of lms processes for your server.  Please make sure that the total number of lms processes 
    of all databases on the server is less than the total number of CPUs/cores on the server.  
    Please refer to the Document 558185.1 
    It's a static parameter and rolling restart is supported.

Increasing _lm_sync_timeout avoids instance evictions when some reconfiguration steps take longer than expected due to the large SGA.  
  Setting _lm_sync_timeout also changes the default setting of _lm_rcfg_timeout that is set to 3 times _lm_sync_timeout.  
  This will prevent some steps from timing out altogether.

_lm_tickets allocates the number of flow control tickets that lms uses to send messages.  
  The default setting is 1000.   
  Allocating more tickets (used for sending messages) avoids issues such as seen in BUG#16088176.  
  The suggestion is to set _lm_tickets to 8000 for databases with large sga even if the patch for the bug _lm_tickets is applied.  E

Setting _gc_policy_minimum to 15000 or larger makes DRM to occur much less frequently.  
  Setting this is preferable than disabling the DRM for most databases.
	--[[
		@CHECK_USER_SYSDBA: SYSDBA={},default={--} 
    @check_access_traffic: {
          GV$GES_TRAFFIC_CONTROLLER={GV$GES_TRAFFIC_CONTROLLER}
          SYS.x$kjitrft={
              SELECT inst_id,
                   kjitrftlid LOCAL_NID,
                   kjitrftrid REMOTE_NID,
                   kjitrftrrd REMOTE_RID,
                   kjitrftinc REMOTE_INC,
                   kjitrftta TCKT_AVAIL,
                   kjitrfttl TCKT_LIMIT,
                   kjitrfttr TCKT_RCVD,
                   decode(kjitrfttw, 0, 'NO', 'YES') TCKT_WAIT,
                   kjitrftss SND_SEQ_NO,
                   kjitrftsr RCV_SEQ_NO,
                   kjitrftst STATUS
            FROM   table(gv$(cursor(select * from SYS.x$kjitrft)))
          }
      }
	--]]
]]*/
SET FEED OFF
select * from (&check_access_traffic);

&CHECK_USER_SYSDBA sys param gcs_server_processes _lm_tickets _gc_policy_minimum _lm_sync_timeout