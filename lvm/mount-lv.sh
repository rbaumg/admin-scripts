#!/bin/bash
# Mounts a logical volume containing a whole disk (i.e. multiple partitions)
# Uses kpartx to manage block device mappings
#
MOUNTPOINT="/tmp/lvm"

VOLUME="$1"
if [ -z "$1" ]; then
   echo >&2 "Usage: $0 <lv-path> [mountpoint]"
   exit 1
fi
if [ ! -z "$2" ]; then
  MOUNTPOINT="$2"
fi

hash kpartx 2>/dev/null || { echo >&2 "You need to install kpartx. Aborting."; exit 1; }
hash blkid 2>/dev/null || { echo >&2 "You need to install util-linux. Aborting."; exit 1; }
hash awk 2>/dev/null || { echo >&2 "You need to install awk. Aborting."; exit 1; }

# check if superuser
if [[ $EUID -ne 0 ]]; then
   echo >&2 "This script must be run as root."
   exit 1
fi

# Validate mountpoint
if [ ! -e "${MOUNTPOINT}" ]; then
  echo >&2 "ERROR: Mount directory '${MOUNTPOINT}' does not exist."
  exit 1
fi

function getSize() {
  re='^[0-9]+$'
  if ! [[ $1 =~ $re ]] ; then
    echo "NaN"
  fi

  if [ $1 -lt 1000 ]; then
    echo "${1} bytes"
  fi

  echo $1 |  awk '
    function human(x) {
        if (x<1000) {return x} else {x/=1024}
        s="kMGTEPZY";
        while (x>=1000 && length(s)>1)
            {x/=1024; s=substr(s,2)}
        return int(x+0.5) substr(s,1,1)
    }
    {sub(/^[0-9]+/, human($1)); print}'
}

# Determine mappings that will be generated by kpartx
KPARTX_LIST=`kpartx -l ${VOLUME} | awk '{ print $1 }'`
if ! [ $? -eq 0 ]; then
  echo >&2 "ERROR: Failed to determine kpartx mappings for ${VOLUME}."
  exit 1
fi

declare -a mappings=();
for part in ${KPARTX_LIST}; do
  map="/dev/mapper/${part}"
  mappings=("${mappings[@]}" "${map}")
done

# Create mappings
if ! kpartx -as ${VOLUME}; then
  echo >&2 "ERROR: Failed to create mappings for ${VOLUME}."
  exit 1
fi

TOTAL_SIZE=0
TOTAL_MOUNTED=0

# Print out mappings
declare -a mounted=();
for ((idx=0;idx<=$((${#mappings[@]}-1));idx++)); do
  map=${mappings[$idx]}
  dev=$(readlink -e ${map})
  mnt=$(basename ${map})
  if [ ! -b "$dev" ]; then
    echo >&2 "WARNING: '${map}' does not point to a valid block device."
  fi
  if [ ! -z "$(mount | grep ${mnt})" ]; then
    echo >&2 "ERROR: '${map}' is already mounted; aborting..."
    exit 1
  fi

  BLKID=$(blkid "${map}")
  FSTYPE=$(echo $BLKID | grep -Po '(?<=TYPE\=\")[A-Za-z0-9\-\_\s]+(?=\")')
  LABEL=$(echo $BLKID | grep -Po '(?<=LABEL\=\")[A-Za-z0-9\-\_\s]+(?=\")')
  SIZE=$(blockdev --getsize64 "${map}")

  MNT_PATH="${MOUNTPOINT}/${mnt}"
  if [ -e "${MNT_PATH}" ]; then
    echo >&2 "WARNING: The path '${MNT_PATH}' already exists; skipping..."
  else
    mkdir "${MNT_PATH}"
    mount "${dev}" "${MNT_PATH}"
    if ! [ $? -eq 0 ]; then
      echo >&2 "ERROR: Failed to mount ${map}."
    else
      ((TOTAL_MOUNTED++))
      TOTAL_SIZE=$((${TOTAL_SIZE}+${SIZE}))
      mounted=("${mounted[@]}" "${MNT_PATH}")
      if [ -z "${LABEL}" ]; then
        printf "Mounted %s -> %s (Type: %s, Size: %s)\n" "${mnt}" "${MNT_PATH}" "${FSTYPE}" "$(getSize ${SIZE})"
      else
        printf "Mounted %s -> %s (Type: %s, Size: %s, Label: %s)\n" "${mnt}" "${MNT_PATH}" "${FSTYPE}" "$(getSize ${SIZE})" "${LABEL}"
      fi
    fi
  fi
done

printf "Mounted %i partitions totaling %s in size.\n" ${TOTAL_MOUNTED} $(getSize ${TOTAL_SIZE})

exit 0
