#!/bin/bash

#############################################################
# Linux Client Uninstaller Script
#############################################################
# Constants
readonly ERROR=0
readonly WARN=1
readonly INFO=2
readonly DEBUG=3
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="${0:0:${#0}-${#SCRIPT_NAME}}"
readonly INIT_D_DIR="/etc/init.d"
readonly IS_ROOT=$([[ $(id -u) -eq 0 ]] && echo true || echo false)
readonly REQ_CMDS="cut find id grep ls rm sed"

# Resource locations
APP_DIR=
BIN_DIR=
INSTALL_DIR=
INSTALL_VARS_FILE="install.vars"
MANIFEST_DIR=

# Naming dependent on sourcing install variables file
APP_SERVICE_NAME=

# Config
APP_BASENAME="CrashPlan"
DEFAULT_YES="false"
LEAVE_APP_DATA="false"
LOG_LEVEL=${INFO}
LOG_FILE=
QUIET="false"
TARGET_USER=
USER_INSTALL="false"

function log_level_to_string() {
  case $1 in
  ${ERROR})
    echo "Error"
    ;;
  ${WARN})
    echo "Warning"
    ;;
  ${INFO})
    echo "Info"
    ;;
  ${DEBUG})
    echo "Debug"
    ;;
  *)
    echo "Unknown"
    ;;
  esac
}

function log() {
  if [[ $1 -gt ${LOG_LEVEL} ]] || [[ -z "${LOG_FILE}" && "${QUIET}" == "true" ]]; then
    return 0
  fi

  local time_stamp=$(date)
  local level=$(log_level_to_string "$1")
  local message=$2
  local log_message="$time_stamp: $level : $message"

  if [[ -n "${LOG_FILE}" ]]; then
    echo "$log_message" >>${LOG_FILE}
  elif [[ "${QUIET}" == "false" ]]; then
    echo "$log_message"
  fi
}

function usage() {
  echo "Usage: $0 -i path [-dhqxy] [-l file] [-u user]"
  echo "${APP_BASENAME} Uninstaller"
  echo
  echo "     -h                 Print usage statement."
  echo "     -i [install_path]  Installation path of the agent [default: /usr/local/crashplan]."
  echo "     -l [log_file]      Relative or absolute path to log file [default: stdout]."
  echo "     -q                 Suppress all output."
  echo "     -u [user]          Provide a target user for a user instance uninstall"
  echo "     -v                 Add debug lines to the output."
  echo "     -x                 Leave application data for reinstall or upgrade."
  echo "     -y                 Answer yes to all prompts. If suppressing output, the default is no."
  echo
}

function set_install_resources() {
  readonly INSTALL_DIR=${1%/}
  if [[ ! -d "${INSTALL_DIR}" ]]; then
    log ${ERROR} "Install path: '${INSTALL_DIR}' does not exist. Please ensure the correct install path was provided."
    exit 1
  fi

  readonly INSTALL_VARS_FILE="${INSTALL_DIR}/${INSTALL_VARS_FILE}"
  if [[ ! -f "${INSTALL_VARS_FILE}" ]]; then
    log ${ERROR} \
      "Install variables file: '${INSTALL_VARS_FILE}' does not exist. Please ensure the correct install path was provided."
    exit 1
  fi

  log ${DEBUG} "Installation directory: '${INSTALL_DIR}'"
  log ${DEBUG} "Installation variables file: '${INSTALL_VARS_FILE}'"
}

function verify_target_user_dir() {
  if [[ ! -d "/home/${TARGET_USER}" ]]; then
    log ${ERROR} "Targeted user's home directory does not exist: '/home/${TARGET_USER}'"
    exit 1
  fi
}

function process_input() {
  local install_path="/usr/local/crashplan"
  while getopts "hi:l:qu:xvy" opt; do
    case ${opt} in
    h)
      usage
      exit 0
      ;;
    i) readonly install_path="$OPTARG" ;;
    l)
      LOG_FILE="$OPTARG"
      if [[ -f ${LOG_FILE} ]]; then
        log ${INFO} "============================================================================"
        log ${INFO} "                            Starting Uninstall"
        log ${INFO} "============================================================================"
      fi
      ;;
    q) QUIET="true" ;;
    u)
      USER_INSTALL="true"
      TARGET_USER="$OPTARG"
      ;;
    x) LEAVE_APP_DATA="true" ;;
    v) LOG_LEVEL=${DEBUG} ;;
    y) DEFAULT_YES="true" ;;
    \?)
      usage
      exit 1
      ;;
    esac
  done
  log ${DEBUG} "${SCRIPT_NAME} ran with arguments $*"
  log ${DEBUG} "Keeping app data: ${LEAVE_APP_DATA}"

  shift $((OPTIND - 1))

  readonly DEFAULT_YES
  readonly LEAVE_APP_DATA
  readonly LOG_FILE
  readonly LOG_LEVEL
  readonly TARGET_USER
  readonly USER_INSTALL

  if [[ -n "${TARGET_USER}" ]]; then
    verify_target_user_dir
  fi
  set_install_resources "${install_path}"
}

function verify_cmds() {
  local missing_cmds
  for cmd in ${REQ_CMDS}; do
    if ! hash "${cmd}" &>/dev/null; then
      missing_cmds="${missing_cmds} '${cmd}'"
    fi
  done
  if [[ -n "${missing_cmds}" ]]; then
    log ${ERROR} "Missing command(s) required for install:${missing_cmds}"
    exit 1
  fi
}

function verify_user() {
  log ${DEBUG} "Uninstalling as '$(whoami)'"
  log ${DEBUG} "User uninstall: ${USER_INSTALL}"
  if ! ${USER_INSTALL} && [[ ${IS_ROOT} == "false" ]]; then
    log ${ERROR} "Insufficient privileges. Running as '${USER}'"
    log ${ERROR} "Please run as root or specify user only install."
    exit 1
  fi
}

function set_custom_names() {
  readonly APP_DIR=${TARGETDIR}
  readonly BIN_DIR=${BINSDIR}
  readonly MANIFEST_DIR=${MANIFESTDIR}
  readonly APP_SERVICE_NAME="service.sh"
}

# Global variables defined in install.vars
# TARGETDIR       Install directory of the application
# MANIFESTDIR     Location of the backup manifest
# INITDIR         init.d directory. Should be the same on all systems.
#                 !!!! NOTE: This is an outdated place for putting service scripts on systemd distros !!!!
# INSTALLDATE
# APP_BASENAME
# DIR_BASENAME
# JAVACOMMON      Location of the application-supplied jdk
function source_install_vars() {
  if [[ ! -f "${INSTALL_VARS_FILE}" ]]; then
    log ${ERROR} "${INSTALL_VARS_FILE} missing"
    exit 1
  fi

  source "${INSTALL_VARS_FILE}"

  readonly DIR_BASENAME
  readonly APP_BASENAME
  readonly APP_BASENAME_LOWER="$(echo "${APP_BASENAME}" | tr '[:upper:]' '[:lower:]')"

  # Temporary work around for variable names
  set_custom_names

  log ${INFO} "Application directory: '${APP_DIR}'"
  log ${INFO} "Binary directory: '${BIN_DIR}'"
  log ${INFO} "Manifest directory: '${MANIFEST_DIR}'"
  log ${INFO} "Application basename: '${APP_BASENAME}'"
  log ${INFO} "Application directory basename: '${DIR_BASENAME}'"

  if [[ -z "${DIR_BASENAME}" || -z "${APP_BASENAME}" || -z "${APP_DIR}" ]]; then
    log ${ERROR} "Missing install location information from '${INSTALL_VARS_FILE}'"
    log ${ERROR} "See above location values."
    exit 1
  fi
}

function get_yn_response() {
  local yn
  if [[ "${QUIET}" == "false" ]] && [[ "${DEFAULT_YES}" == "false" ]]; then
    read -r yn
  fi

  if [[ -z "${yn}" ]]; then
    if [[ "${DEFAULT_YES}" == "true" ]]; then
      yn=y
      [[ "${QUIET}" == "false" ]] && echo
    else
      yn=n
    fi
  fi

  case ${yn} in
  [Yy] | [Yy][Ee][Ss]) yn=y ;;
  *) yn=n ;;
  esac

  eval "$1=\$yn"
}

function prompt_user_to_continue() {
  if [[ "${QUIET}" == "false" ]]; then
    echo
    echo "============================================================================"
    echo "        !!! WARNING !!!     Software Removal     !!! WARNING !!!"
    echo "============================================================================"
    echo "This uninstall will remove ${APP_BASENAME} software and configuration."
    echo "Existing backups are not affected, but backup processes will stop."
    echo
    echo -n "Are you sure you wish to continue? (yes/no) [no] "
  fi

  get_yn_response YN
  if [[ ${YN} != "y" ]]; then
    log ${INFO} "Your choice to continue, '${YN}', was not recognized as yes."
    log ${INFO} "${APP_BASENAME} was not uninstalled."
    exit 0
  fi
}

function stop_service() {
  log ${DEBUG} "Issuing service command: '${APP_DIR}/bin/${APP_SERVICE_NAME} stop'"
  if [[ -f "${APP_DIR}/electron/code42" ]]; then
    pkill -f "${APP_DIR}/electron/code42"
  fi
  if [[ -f "${APP_DIR}/electron/crashplan" ]]; then
    pkill -f "${APP_DIR}/electron/crashplan"
  fi		
  if "${APP_DIR}/bin/${APP_SERVICE_NAME}" stop &>/dev/null; then
    log ${INFO} "${APP_BASENAME} stopped successfully"
  else
    log ${WARN} "Failed to stop ${APP_SERVICE_NAME}"
  fi
}

function retain_if_desired() {
  local node=$1
  if [[ -n "$(ls "${node}")" ]]; then
    if [[ "${node}" == *manifest || "${node}" == *backupArchives ]]; then
      log ${DEBUG} "Retaining $node"
      return 0
    elif [[ "${LEAVE_APP_DATA}" == "true" ]] && [[ "${node}" == *log || "${node}" == *conf ||
      "${node}" == *cache || "${node}" == *metadata || "${node}" == *upgrade ||
      "${node}" == *print_job_data ]]; then
      log ${DEBUG} "Retaining $node"
      return 0
    fi
  fi
  log ${DEBUG} "Removing $node"
  rm -rf "${node}"
}

function clean_app_dir() {
  if [[ -z "${APP_DIR}" || -z "${DIR_BASENAME}" ]]; then
    log ${ERROR} "Install location information missing."
    log ${ERROR} "Application directory: ${APP_DIR}"
    log ${ERROR} "Application directory basename: ${DIR_BASENAME}"
    exit 1
  fi

  if [[ "${APP_DIR}" != *"${DIR_BASENAME}"* ]]; then
    log ${ERROR} "Application install directory is not properly formed. Something may be wrong."
    exit 1
  fi

  for child in "${APP_DIR}"/*; do
    [[ -e "${child}" ]] || continue
    retain_if_desired "${child}"
  done

  # If leaving the data we want to keep the /conf dir as it contains the tmp and udb dir.
  # It also contains the default.service.xml and service.log.xml files which do occationally change.
  # We need to remove these so that upgrades will add the latest from the package.
  if [[ "${LEAVE_APP_DATA}" == "true" ]]; then
    rm -f "${APP_DIR}/conf/default.service.xml"
    rm -f "${APP_DIR}/conf/service.log.xml"
    log ${INFO} "Removed '${APP_DIR}/conf/default.service.xml'"
    log ${INFO} "Removed '${APP_DIR}/conf/service.log.xml'"
  fi

  if [[ -z $(ls "${APP_DIR}") ]]; then
    log ${DEBUG} "Removing ${APP_DIR}"
    rm -rf "${APP_DIR}"
  fi
}

function remove_desktop_launchers() {
  local launcher_file_name="${APP_BASENAME_LOWER}.desktop"

  if [[ "${USER_INSTALL}" == "false" ]]; then
    rm -f "/usr/share/applications/${launcher_file_name}"
    log ${INFO} "Removed '/usr/share/applications/${launcher_file_name}'"
  else
    find "/home/${TARGET_USER}/.local" -iname "${launcher_file_name}" -exec rm -f "{}" \;
    log ${INFO} "Removed '/home/${TARGET_USER}/.local/${launcher_file_name}'"
  fi
}

function remove_electron_configs() {
  if [[ "${USER_INSTALL}" == "false" ]]; then
    for electron_config in /home/*/.config/"${APP_BASENAME}"; do
      [[ -e "${electron_config}" ]] || continue
      log ${DEBUG} "Removing ${electron_config}"
      rm -rf "${electron_config}"
    done
  else
    log ${DEBUG} "Removing /home/${TARGET_USER}/.config/${APP_BASENAME}"
    rm -rf "/home/${TARGET_USER}/.config/${APP_BASENAME}"
  fi
}

function strip_keys_from_identity_file() {
  local identity_file
  [[ ${USER_INSTALL} == "true" ]] && identity_file="/home/${TARGET_USER}/.${DIR_BASENAME}/.identity" ||
    identity_file="/var/lib/${DIR_BASENAME}/.identity"
  if [[ -f ${identity_file} ]]; then
    log ${DEBUG} "Removing keys from identity file: '${identity_file}'"
    sed -i -e '/DataKey/Id' -e '/SecureDataKey/Id' -e '/PrivateKey/Id' -e '/PublicKey/Id' \
      -e '/SecurityKeyType/Id' -e '/OfflinePasswordHash/Id' "${identity_file}"
  fi
}

function remove_init_d_links() {
  log ${INFO} "Remove from init.d"
  for level in 0 1 2 3 4 5 6; do
    log ${DEBUG} "Removing '/etc/rc${level}.d/[KkSs]99${APP_BASENAME_LOWER}'"
    if ! rm -f /etc/rc${level}.d/[KkSs]99"${APP_BASENAME_LOWER}"; then
      log ${WARN} "Failed to remove link '/etc/rc${level}.d/[KkSs]99${APP_BASENAME_LOWER}'"
    fi
  done
  rm -f "${INIT_D_DIR}/${APP_BASENAME_LOWER}"
}

function remove_systemd_unit_file() {
  log ${INFO} "Remove from systemd"
  if ! systemctl stop "${APP_BASENAME_LOWER}" &>/dev/null; then
    log ${WARN} "Failed to stop the ${APP_BASENAME_LOWER} service."
  fi
  if ! systemctl disable "${APP_BASENAME_LOWER}" &>/dev/null; then
    log ${WARN} "Failed to disable the ${APP_BASENAME_LOWER} service."
  fi
  local path="/etc/systemd/system/${APP_BASENAME_LOWER}.service"
  if [[ -f "${path}" ]]; then
    log ${DEBUG} "Removing $path"
    if ! rm -f "${path}"; then
      log ${WARN} "Failed to remove systemd unit file '${path}'"
    fi
  fi
  systemctl daemon-reload &>/dev/null
  systemctl reset-failed &>/dev/null
}

function remove_resources() {
  if [[ "${USER_INSTALL}" == "false" ]]; then
    if systemctl --all --type service | grep -q "${APP_BASENAME_LOWER}"; then
      remove_systemd_unit_file
    else
      remove_init_d_links
    fi
    rm -f "${BIN_DIR}/${APP_BASENAME}Desktop"
    rm -f "/usr/local/bin/${APP_BASENAME_LOWER}"
  fi

  clean_app_dir
  remove_desktop_launchers

  if [[ "${LEAVE_APP_DATA}" == "false" ]]; then
    remove_electron_configs
    strip_keys_from_identity_file
    rm -f" /var/lib/${DIR_BASENAME}/.ui_info"
    rm -f" /var/lib/${DIR_BASENAME}/service.pem"
  fi
}

function log_completion_message() {
  log ${INFO} "${APP_BASENAME} uninstalled."
}

#########################################
# Script Begin
#########################################
# shellcheck disable=SC2068
process_input $@
verify_cmds
verify_user
source_install_vars
prompt_user_to_continue
stop_service
remove_resources
log_completion_message
