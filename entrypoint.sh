#!/bin/bash

if [ ! -e "${SNAPSHOT_LOCATION}" ]; then
  echo "ERROR: The snapshot location '${SNAPSHOT_LOCATION}' was not found." \
       "Please check the SNAPSHOT_LOCATION environment variable."
  exit
fi

if [ -z "${SNAPSHOT_DESTINATION}" ]; then
  echo "ERROR: The s3 destination '${SNAPSHOT_DESTINATION}' was not set." \
       "Please check the SNAPSHOT_DESTINATION environment variable."
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

toLower() {
  echo "$@" | tr '[A-Z]' '[a-z]'
}

SNAPSHOT_COMPRESSION=$(toLower ${SNAPSHOT_COMPRESSION})
if [ "${SNAPSHOT_COMPRESSION}" == "" ]; then
  SNAPSHOT_COMPRESSION='tar'
fi

FILENAME_EXT=
case ${SNAPSHOT_COMPRESSION} in
  "tar") FILENAME_EXT='tgz' ;;
  "zip") FILENAME_EXT='zip' ;;
  *) echo "Error processing filename extension" && exit ;;
esac

BACKUP_DIR=/backups

DEBUG=$(toLower ${DEBUG-FALSE})
log() {
    [[ "$DEBUG" == "true" ]] && echo "DEBUG:" $@ >&2
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

s3_cp() {
  aws s3 cp --quiet $@
}
s3_ls() {
  aws s3 ls $@ | awk '{print $4}'
}
s3_rm() {
  aws s3 rm --quiet $@
}

if [ "${SNAPSHOT_METHOD}" = "local" ]; then
  CP=local_cp
  LS=local_ls 
  RM=local_rm
  export -f local_rm
elif [ "${SNAPSHOT_METHOD}" = "s3" ]; then
  CP=s3_cp
  LS=s3_ls 
  RM=s3_rm
  export -f s3_rm
else
  echo "Error: Unknown SNAPSHOT_METHOD '${SNAPSHOT_METHOD}'"
  exit
fi

echo "Snapshot Tool"
echo "-------------"
echo "SNAPSHOT_NAME=${SNAPSHOT_NAME}"
echo "SNAPSHOT_TIMESTAMP_FORMAT=${SNAPSHOT_TIMESTAMP_FORMAT}"
echo "SNAPSHOT_INTERVAL=${SNAPSHOT_INTERVAL}"
echo "SNAPSHOT_MAX_NUM=${SNAPSHOT_MAX_NUM}"
echo "SNAPSHOT_LOCATION=${SNAPSHOT_LOCATION}"
echo "SNAPSHOT_DESTINATION=${SNAPSHOT_DESTINATION}"
echo "SNAPSHOT_METHOD=${SNAPSHOT_METHOD}"
echo "SNAPSHOT_COMPRESSION=${SNAPSHOT_COMPRESSION}"
echo "DEBUG=${DEBUG}"
echo

cleanup() {
  snap_list=$(${LS} ${SNAPSHOT_DESTINATION}/ | sort | grep ${SNAPSHOT_NAME}-.*\.${FILENAME_EXT})
  total=$(($(echo "${snap_list}" | wc -l)-1))

  old_snaps=$(echo "${snap_list}" | head -n -${NUM_TO_KEEP})
  num_old=$(echo "${old_snaps}" | wc -l)
  
  if [ ! -z "${old_snaps}" ]; then
    echo "Found ${total} snapshots, ${num_old} greater than ${SNAPSHOT_MAX_NUM} deleting" $old_snaps
    echo "${old_snaps}" | xargs -L1 -i bash -c "${RM} ${SNAPSHOT_DESTINATION}/{}" _
  fi
}

is_different() {
  previous_filename=${BACKUP_DIR}/${SNAPSHOT_NAME}-previous.${FILENAME_EXT}
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
  FILENAME=${SNAPSHOT_NAME}-${TIMESTAMP}.${FILENAME_EXT}

  echo "Archiving ${SNAPSHOT_LOCATION} to ${FILENAME}"

  files=$(find ${SNAPSHOT_LOCATION} -maxdepth 1 -printf '%P ') 

  case ${SNAPSHOT_COMPRESSION} in
    "tar")
      tar c --directory=${SNAPSHOT_LOCATION} ${files} | gzip -n >${BACKUP_DIR}/${FILENAME} 
      log "Backup Contents:" $(tar tf ${BACKUP_DIR}/${FILENAME})
      ;;
    "zip")
      cd ${SNAPSHOT_LOCATION} && zip -X -q ${BACKUP_DIR}/${FILENAME} ${files} 
      log "Backup Contents:" $(unzip -Z1 ${BACKUP_DIR}/${FILENAME})
      ;;
    *) echo "Error: No compression setting found, should not be here" && exit ;; 
  esac

  is_different ${BACKUP_DIR}/${FILENAME}
  if [ $? -eq 0 ]; then
    log "Snapshot different than the last one"
    echo "Copying ${FILENAME} to ${SNAPSHOT_DESTINATION}"

    ${CP} ${BACKUP_DIR}/${FILENAME} ${SNAPSHOT_DESTINATION}/

    ${CP} ${SNAPSHOT_DESTINATION}/${FILENAME} ${SNAPSHOT_DESTINATION}/${SNAPSHOT_NAME}-latest.${FILENAME_EXT}

    cleanup
  else
    echo "Snapshot same as the last one, skipping backup"
  fi

  rm ${BACKUP_DIR}/${FILENAME}
}

if [ ! -z "${SNAPSHOT_INTERVAL}" ]; then
  sleep 120
  while true 
  do
    run
    sleep ${SNAPSHOT_INTERVAL}
  done
else
  run
fi