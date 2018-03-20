#!/bin/sh

if [ $# -ne 2 ]; then
        echo " $0  arguments: -exec <executable> | -pid <pid>"
        exit 1
fi

export TZ=UTC

echo " starting: "
echo " $0 $1 $2 ($#)"
date
uname -a

WATCHPID=
if [ $1 == "-exec" ]; then
  # overwrite: it is the service that we are searching
  WATCHPROC=cardano-node
  WATCHPID=`systemctl show ${WATCHPROC} -p MainPID --value`
fi

if [ $1 == "-pid" ]; then
  WATCHPID=$2
  WATCHPROC=cardano-node
fi

if [ -z "${WATCHPID}" ]; then
        echo " No service ${WATCHPROC} found."
        exit 1
fi

echo "  watching service ${WATCHPROC} with PID ${WATCHPID}"
echo

PAGESIZE=`getconf PAGESIZE`
CLKTCK=`getconf CLK_TCK`
echo "PAGESIZE=${PAGESIZE} CLKTCK=${CLKTCK}"
echo

SLEEPTIME=5
RECNAME1=statm
RECNAME2=stat
RECNAME3=io
PROC=/proc/$WATCHPID

while [ -e ${PROC}/${RECNAME1} ]; do
        NOW=`date +%s`
        { echo -n "${NOW} ${RECNAME1} " && cat ${PROC}/${RECNAME1}; }
        { echo -n "${NOW} ${RECNAME2} " && cat ${PROC}/${RECNAME2}; }
        { echo -n "${NOW} ${RECNAME3} " && cat ${PROC}/${RECNAME3} | cut -d " " -f 2 | tr '\n' ' ' && echo; }
        sleep $SLEEPTIME
done

echo
#cat $PROC/status
#date
#echo " $0 done."
