#!/bin/bash
FOLDER=$1
TARGET=${FOLDER}1
SOURCE=/media/sf_D_DRIVE/jdk_linux
JAR=$SOURCE/bin/jar
if [ ! -d "$SOURCE" ]; then
  echo "No such JRE directory: $SOURCE"
  exit 1
fi

if [ ! -x "$JAR" ]; then
  echo "Cannot find executable program: $JAR"
  exit 1
fi

cd ../dump
rm -rf $TARGET ${FOLDER}.jar temp
rm -rf ${FOLDER}.jar
cp -r $FOLDER $TARGET
find $TARGET -name "*.class"| xargs rm -f
mkdir temp
cd temp
find $SOURCE -name "$FOLDER.jar"|xargs $SOURCE/bin/jar xf
cd ..
for f in `find $FOLDER -type f -name "*.*"`; do
    sub=`echo $f|sed "s/^$FOLDER//"`
    cp -r temp${sub} ${TARGET}${sub}
done
cd $TARGET
$SOURCE/bin/jar cnf ../${FOLDER}.jar *
cd ..
rm -rf $TARGET temp
cp ${FOLDER}.jar ../jre_linux/lib