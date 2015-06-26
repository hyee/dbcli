-- edb360 configuration file. for those cases where you must change edb360 functionality

/*************************** ok to modify (if really needed) ****************************/

-- history days (default 31)
DEF edb360_conf_days = '31';

-- range of dates below superceed history days when values are other than YYYY-MM-DD
DEF edb360_conf_date_from = 'YYYY-MM-DD';
DEF edb360_conf_date_to = 'YYYY-MM-DD';

-- working hours are defined between these two HH24MM values (i.e. 7:30AM and 7:30PM)
DEF edb360_conf_work_time_from = '0730';
DEF edb360_conf_work_time_to = '1930';

-- working days are defined between 1 (Sunday) and 7 (Saturday)
DEF edb360_conf_work_day_from = '2';
DEF edb360_conf_work_day_to = '6';

-- maximum time in hours to allow edb360 to execute
DEF edb360_conf_max_hours = '24';

/**************************** not recommended to modify *********************************/

-- excluding report types reduce usability while providing marginal performance gain
DEF edb360_conf_incl_html = 'Y';
DEF edb360_conf_incl_text = 'Y';
DEF edb360_conf_incl_csv = 'Y';
DEF edb360_conf_incl_line = 'Y';
DEF edb360_conf_incl_pie = 'Y';

-- excluding awr reports substantially reduces usability with minimal performance gain
DEF edb360_conf_incl_awr_rpt = 'Y';
DEF edb360_conf_incl_addm_rpt = 'Y';
DEF edb360_conf_incl_ash_rpt = 'Y';
DEF edb360_conf_incl_tkprof = 'Y';

-- top sql to execute further diagnostics (range 0-128)
DEF edb360_conf_top_sql = '48';
DEF edb360_conf_planx_top = '48';
DEF edb360_conf_sqlmon_top = '0';
DEF edb360_conf_sqlash_top = '0';
DEF edb360_conf_sqlhc_top = '0';
DEF edb360_conf_sqld360_top = '16';

/**************************** enter your modifications here *****************************/

--DEF edb360_conf_date_from = '2015-03-01';
--DEF edb360_conf_date_to = '2015-03-10';

--DEF edb360_conf_incl_text = 'N';
--DEF edb360_conf_incl_csv = 'N';

