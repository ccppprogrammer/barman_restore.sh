#!/bin/bash

WORKING_DIR="/var/lib/postgresql/bin/restore"
LOG_FILENAME="${WORKING_DIR}/barman_restore.log"
SSH_BIN="/usr/bin/ssh"
JQ_BIN="/usr/bin/jq"

function log() {
	echo "$(date +'%Y-%m-%d %H:%M:%S %Z'): $1" &>> ${LOG_FILENAME}
	echo "$(date +'%Y-%m-%d %H:%M:%S %Z'): $1"
}

function usage() {
	if [ -n "$1" ]; then
		echo "$1";
		echo ""
	fi
	echo "Usage: $0 [-b barman-hostname] [-s barman-pgsql-server-name] [-i barman-backup-id|latest] [-t target-time] [-D destination-directory] [-r remote-ssh-command]"
	echo "  -b, --barman-hostname             Barman hostname"
	echo "  -s, --barman-pgsql-server-name    Barman's PostgreSQL server name"
	echo "  -i, --barman-backup-id            Barman backup ID or latest"
	echo "  -t, --target-time                 Barman backup time. You can use any valid unambiguous representation. e.g: \"YYYY-MM-DD HH:MM:SS.mmm\""
	echo "  -D, --destination-directory       Directory where the new server is created"
	echo "  -r, --remote-ssh-command          Secure shell command to be launched on a remote host"
	echo "  -?, --help                        Display this help"
	echo ""
	echo "Example: $0 -b barman.domain.com -s pgsql -i latest -D /var/lib/postgresql/12/main/ -r \"ssh postgres@127.0.0.1 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -i /var/lib/barman/.ssh/id_rsa\""
	echo ""
	exit 1
}


if [[ "$#" -eq "0" ]]; then
	usage
fi

CMD="$0 $*"
while [[ "$#" -gt "0" ]]; do
	case $1 in
		-b|--barman-hostname) BARMAN_HOSTNAME="$2"; shift 2;;
		-b=*|--barman-hostname=*) BARMAN_HOSTNAME="${1#*=}"; shift;;
		-s|--barman-pgsql-server-name) BARMAN_PGSQL_SERVER_NAME="$2"; shift 2;;
		-s=*|--barman-pgsql-server-name=*) BARMAN_PGSQL_SERVER_NAME="${1#*=}"; shift;;
		-i|--barman-backup-id) BARMAN_BACKUP_ID="$2"; shift 2;;
		-i=*|--barman-backup-id=*) BARMAN_BACKUP_ID="${1#*=}"; shift;;
		-t|--target-time) BARMAN_TARGET_TIME="$2"; shift 2;;
		-t=*|--target-time=*) BARMAN_TARGET_TIME="${1#*=}"; shift;;
		-D|--destination-directory) DESTINATION_DIRECTORY="$2"; shift 2;;
		-D=*|--destination-directory=*) DESTINATION_DIRECTORY="${1#*=}"; shift;;
		-r|--remote-ssh-command) REMOTE_SSH_COMMAND="\"$2\""; shift 2;;
		-r=*|--remote-ssh-command=*) REMOTE_SSH_COMMAND="${1#*=}"; shift;;
		-\?|--help) usage; shift 2;;
		*) usage "Unknown parameter passed: $1"; shift 2;;
	esac; 
done


log "BEGIN"
log "${CMD}"

if [[ -d "${DESTINATION_DIRECTORY}" ]]; then
	if [[ "$(ls -A ${DESTINATION_DIRECTORY})" ]]; then
		log "ERROR: directory '${DESTINATION_DIRECTORY}' is not empty."
		log "END"
		exit 1
	fi
fi

if [[ "${BARMAN_TARGET_TIME}" == "" ]]; then
	BARMAN_TARGET_TIME=$(${SSH_BIN} barman@${BARMAN_HOSTNAME} "barman -f json show-backup ${BARMAN_PGSQL_SERVER_NAME} ${BARMAN_BACKUP_ID}" | ${JQ_BIN} -r '.[] | .base_backup_information | .end_time')
fi

if ! [[ ${BARMAN_TARGET_TIME} =~ ^[0-9]{4}\-[0-9]{2}\-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}.*$ ]]; then
	log "ERROR: incorrect BARMAN_TARGET_TIME='${BARMAN_TARGET_TIME}'."
	log "END"
	exit 1
fi

BARMAN_RECOVER_OUTPUT=$(${SSH_BIN} barman@${BARMAN_HOSTNAME} "barman recover --target-time \"${BARMAN_TARGET_TIME}\" --target-action promote --remote-ssh-command ${REMOTE_SSH_COMMAND} ${BARMAN_PGSQL_SERVER_NAME} ${BARMAN_BACKUP_ID} ${DESTINATION_DIRECTORY}" 2>&1)
log "${BARMAN_RECOVER_OUTPUT}"
log "Delete .barmans3 files..."
FIND_OUTPUT=$(find "${DESTINATION_DIRECTORY}" -name ".barmans3" -type f -print -delete)
log "${FIND_OUTPUT}"

log "END"
exit 0
