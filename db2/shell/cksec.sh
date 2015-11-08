#!/bin/bash
:<<DESC
# Shows the security in the Operative System related to the users and groups in DB2.
#
# 2013-05-31 Andres Gomez - Script creation.
# 2013-06-17 Andres Gomez - Dynamic group analyzes.
DESC

INSTALL_DIR=/opt/db2/na/9.7.4

# Shows the members of a OS group.
group () {
  GROUP=$(echo $1 | tr '[A-Z]' '[a-z]')
  LINE=$(awk -F: "/^${GROUP}:/ {print \$3\":\"\$4}" /etc/group)
  MEMBERS_SEC=$(echo ${LINE} | cut -d':' -f2)
  ID=$(echo ${LINE} | cut -d':' -f1)
  MEMBERS_PRI=$(awk -F: "/:${ID}:/ {print \$1}" /etc/passwd | sed -e :a -e '$!N; s/\n/, /; ta')
  echo "  Group: ${GROUP} (ID ${ID})"
  echo "   Members: ${MEMBERS_PRI}, ${MEMBERS_SEC}"
}

INSTANCES=$(${INSTALL_DIR}/bin/db2greg -dump | awk -F, '/^I,/ && /,db2ins/ {print $4}')

# Show security at instance level.
echo "Security at instance level:"
while IFS= read INST ; do
  echo "Instance ${INST}"
  eval . ~${INST}/sqllib/db2profile

  while IFS= read LINE ; do
    AUTH=$(echo ${LINE} | cut -d' ' -f1 | sed 's/[(|)]//g')
    GROUP=$(echo ${LINE} | cut -d' ' -f2)
    echo " Authority: ${AUTH}"
    group ${GROUP}
  done < <( db2 get dbm cfg | awk '/_GROUP/ {print $4,$6}' )
done < <( printf '%s\n' "$INSTANCES" )
echo

# Show security at database level.
echo "Security at database level:"
while IFS= read INST ; do
  echo "Instance ${INST}"
  eval . ~${INST}/sqllib/db2profile

  DBS=$(db2 list db directory | awk '/alias/ {print $4}')

  while IFS= read DB ; do
    DB_NAME=$(db2 connect to ${DB} | awk '/alias/ {print $5}')
    if [[ ${DB_NAME} != "" ]] ; then
      echo " Database ${DB}"
      db2 connect to ${DB} > /dev/null
      db2 "select '  ' || substr(grantor,1,10) grantor, substr(grantee,1,10) grantee, granteetype type, dbadmauth dbadm, securityadmauth secadm, wlmadmauth wladm, DATAACCESSAUTH data, ACCESSCTRLAUTH ACCESS, BINDADDAUTH bind, CONNECTAUTH conn, CREATETABAUTH crttab, EXTERNALROUTINEAUTH extrout, IMPLSCHEMAAUTH implschem, LOADAUTH load, NOFENCEAUTH nofenc, QUIESCECONNECTAUTH quiesce, LIBRARYADMAUTH lib, SQLADMAUTH sql, EXPLAINAUTH expl from syscat.dbauth" | grep -e "^$" -v | grep -v "record(s) selected."
      while IFS= read GROUP ; do
        group ${GROUP}
      done < <( db2 connect to ${DB} > /dev/null ; db2 -x "select substr(grantee,1,10) grantee from syscat.dbauth where granteetype = 'G'" )
      db2 terminate > /dev/null
    fi
  done < <( printf '%s\n' "$DBS" )
  db2 terminate > /dev/null

done < <( printf '%s\n' "$INSTANCES" )