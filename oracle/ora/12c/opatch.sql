/*[[List applied patches. Usage: @@NAME [<patch_id>|<bug_id>]
   --[[
      @ver: 12.1={}
   --]]
]]*/

set feed off
SELECT decode(grp,1,nvl2(patchset_id, patchset_id||'/','')||patch_id) patch_id,
       decode(grp,1,patch_uid) patch_uid, 
       decode(grp,1,apply_date) apply_date, 
       decode(grp,1,patch_desc) patch_desc, 
       trim(chr(10) from listagg(sep || bug_id, ',') WITHIN GROUP(ORDER BY seq)) bugs
FROM   (SELECT patchset_id,
               patch_id,
               patch_uid,
               apply_date,
               patch_desc,
               bug_id||DECODE(COUNT(1) OVER(PARTITION BY patch_id),1,'('||bug_desc||')','') bug_id,
               CEIL(seq / 400) grp,
               seq,
               DECODE(MOD(seq-1, 10), 0, CHR(10), '') sep
        FROM   XMLTABLE('/patches/patch' PASSING dbms_qopatch.GET_OPATCH_LIST COLUMNS --
                        patchset_id VARCHAR2(30) PATH 'constituent',
                        patch_ID INT PATH 'patchID',
                        patch_uid INT PATH 'uniquePatchID',
                        apply_Date VARCHAR2(30) PATH 'appliedDate',
                        patch_desc VARCHAR2(300) PATH 'patchDescription',
                        bugs XMLTYPE PATH 'bugs') a,
               XMLTABLE('/bugs/bug' PASSING a.bugs COLUMNS --
                        seq FOR ORDINALITY,
                        bug_id INT PATH '@id',
                        bug_desc VARCHAR2(300) PATH 'description') b
       WHERE :V1 IS NULL or patch_id=:V1 or patch_uid=:V1 or bug_id=:V1)
GROUP  BY patchset_id, patch_id, patch_uid, apply_date, patch_desc, grp;

SELECT patch_id,patch_uid,ACTION,ACTION_TIME,STATUS,VERSION
FROM dba_registry_sqlpatch a
order by ACTION_TIME;

