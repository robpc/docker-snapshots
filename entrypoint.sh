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

log() {
    echo "DEBUG:" $@ >&2
}

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

is_different() {
  previous_filename=${BACKUP_DIR}/${SNAPSHOT_NAME}-previous.tgz
  current_filename=$1

  if [ ! -e "${current_filename}" ]; then
    log "Error: parameter missing to $0"
    return 0
  fi

  if [ -e "${previous_filename}" ]; then
    old_md5=$(md5sum ${previous_filename} | awk '{print $1}')
    new_md5=$(md5sum ${current_filename} | awk '{print $1}')

    log "old ${old_md5} versus new ${new_md5}"
    if [ "$old_md5" = "$new_md5" ]; then
      return 1
    fi
  fi

  cp ${current_filename} ${previous_filename}
  return 0
}

run() {
  TIMESTAMP=`date +${SNAPSHOT_TIMESTAMP_FORMAT}`
  FILENAME=${SNAPSHOT_NAME}-${TIMESTAMP}.tgz

  echo "Archiving ${SNAPSHOT_LOCATION} to ${FILENAME}"

  find ${SNAPSHOT_LOCATION} -maxdepth 1 -printf '%P ' | xargs tar c --directory=${SNAPSHOT_LOCATION} | gzip -n >${BACKUP_DIR}/${FILENAME}

  log "Backup Contents:" $(tar tf ${BACKUP_DIR}/${FILENAME})

  echo "Copying ${FILENAME} to ${SNAPSHOT_S3_DESTINATION}"

  is_different ${BACKUP_DIR}/${FILENAME}
  if [ $? -eq 0 ]; then
    log "Snapshot different than the last one"

    ${CP} ${BACKUP_DIR}/${FILENAME} ${SNAPSHOT_S3_DESTINATION}

    ${CP} ${SNAPSHOT_S3_DESTINATION}/${FILENAME} ${SNAPSHOT_S3_DESTINATION}/${SNAPSHOT_NAME}-latest.tgz

    cleanup
  else
    echo "Snapshot same as the last one, skipping backup"
  fi

  rm ${BACKUP_DIR}/${FILENAME}
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