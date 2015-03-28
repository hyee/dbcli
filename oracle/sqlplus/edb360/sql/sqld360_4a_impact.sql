DEF section_name = 'SQL Performance';
SPO &&sqld360_main_report..html APP;
PRO <h2>&&section_name.</h2>
SPO OFF;

@@sqld360_4b_awr.sql
@@sqld360_4c_ash.sql
--@@sqld360_4b_ash_byevent.sql
--@@&&skip_10g.sqld360_4c_ash_byplanline_event.sql
--@@sqld360_4d_ash_byplanline_obj_event.sql
