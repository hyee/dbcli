#!/bin/bash
FOLDER=$1
if [ "$FOLDER"="" ]; then
  FOLDER=rt
fi

TARGET=${FOLDER}1
SOURCE=/d/jdk_linux
JAR="$SOURCE/bin/jar"



if [ ! -d "$SOURCE" ]; then
  echo "No such JRE directory: $SOURCE"
  exit 1
fi

if [ ! -x "$JAR" ]; then
    if type -p jar &>/dev/null; then
        JAR=jar
    else
        echo "Cannot find executable program: $JAR"
        exit 1
    fi
fi

cd ../dump
echo "Initializing..."
rm -rf $TARGET ${FOLDER}.jar jardump

cp -r $FOLDER $TARGET && find $TARGET -name "*.*"| xargs rm -f &
mkdir jardump
cd jardump
echo "Extracting $FOLDER.jar..."
find "$SOURCE" -name "$FOLDER.jar"|xargs "$JAR" xf
wait
cd ..
echo "Scanning matched files..."
for f in `find $FOLDER -type f`; do
    sub=`echo $f|sed "s/^$FOLDER//"`
    cp -r jardump${sub} ${TARGET}${sub}
done
cd $TARGET
echo "Building new ${FOLDER}.jar..."
"$JAR" cnf ../${FOLDER}.jar *
cd ..
rm -rf $TARGET jardump
cp ${FOLDER}.jar ../jre_linux/lib