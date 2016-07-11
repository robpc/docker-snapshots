#!/bin/bash

if [ ! -e "${SNAPSHOT_LOCATION}" ]; then
  echo "ERROR: The snapshot location '${SNAPSHOT_LOCATION}' was not found." \
       "Please check the SNAPSHOT_LOCATION environment variable."
  exit
fi

if [ -z "${SNAPSHOT_S3_DESTINATION}" ]; then
  echo "ERROR: The s3 destination '${SNAPSHOT_S3_DESTINATION}' was not set." \
       "Please check the SNAPSHOT_S3_DESTINATION environment variable."
  exit
fi

if [ -z "${SNAPSHOT_NAME}" ]; then
  SNAPSHOT_NAME=snapshot
fi

if [ -z "${SNAPSHOT_TIMESTAMP_FORMAT}" ]; then
  SNAPSHOT_TIMESTAMP_FORMAT=%Y%m%d-%H%M%S
fi

if [ -z "${SNAPSHOT_MAX_NUM}" ]; then
  SNAPSHOT_MAX_NUM=5
fi
NUM_TO_KEEP=$((SNAPSHOT_MAX_NUM+1))

BACKUP_DIR=/backups

local_cp() {
  cp $@
}
local_ls() {
  ls --time-style="+%Y-%m-%d %H:%M:%S" -l -g -o $@ | awk '{print $6}' 
}
local_rm() {
  rm $@
}

if [ "${SNAPSHOT_METHOD}" = "local" ]; then
  CP=local_cp
  LS=local_ls 
  RM=local_rm
  export -f local_rm
else
  echo "Error: Unknown SNAPSHOT_METHOD '${SNAPSHOT_METHOD}'"
  exit
fi

cd ${SNAPSHOT_LOCATION}

cleanup() {
  snap_list=$(${LS} ${SNAPSHOT_S3_DESTINATION} | sort | grep ${SNAPSHOT_NAME}-.*\.tgz)
  total=$(($(echo "${snap_list}" | wc -l)-1))

  old_snaps=$(echo "${snap_list}" | head -n -${NUM_TO_KEEP})
  num_old=$(echo "${old_snaps}" | wc -l)
  
  if [ ! -z "${old_snaps}" ]; then
    echo "Found ${total} snapshots, ${num_old} greater than ${SNAPSHOT_MAX_NUM} deleting" $old_snaps
    echo "${old_snaps}" | xargs -L1 -i bash -c "${RM} ${SNAPSHOT_S3_DESTINATION}/{}" _
  fi
}

run() {
  TIMESTAMP=`date +${SNAPSHOT_TIMESTAMP_FORMAT}`
  FILENAME=${SNAPSHOT_NAME}-${TIMESTAMP}.tgz

  echo "Archiving ${SNAPSHOT_LOCATION} to ${FILENAME}"
  tar zcf ${BACKUP_DIR}/${FILENAME} .

  echo "Copying ${FILENAME} to ${SNAPSHOT_S3_DESTINATION}"

  ${CP} ${BACKUP_DIR}/${FILENAME} ${SNAPSHOT_S3_DESTINATION}

  ${CP} ${SNAPSHOT_S3_DESTINATION}/${FILENAME} ${SNAPSHOT_S3_DESTINATION}/${SNAPSHOT_NAME}-latest.tgz

  cleanup
}

if [ ! -z "${SNAPSHOT_INTERVAL}" ]; then
  sleep 10
  while true 
  do
    run
    sleep ${SNAPSHOT_INTERVAL}
  done
else
  run
fi