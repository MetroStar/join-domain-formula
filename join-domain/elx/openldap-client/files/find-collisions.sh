#!/bin/bash
#
set -euo pipefail
#
# Script to locate collisions within an LDAP directory service
#
######################################################################
PROGNAME="$( basename "${0}" )"
BINDPASS="${CLEARPASS:-}"
CRYPTKEY="${CRYPTKEY:-}"
CRYPTSTRING="${CRYPTSTRING:-}"
DEBUGVAL="${DEBUG:-false}"
DIR_DOMAIN="${JOIN_DOMAIN:-}"
DIRUSER="${JOIN_USER:-}"
DOEXIT="0"
DOMAINNAME="${JOIN_DOMAIN:-}"
DS_LIST=()
LDAPTYPE="AD"
LOGFACIL="user.err"
REQ_TLS="${REQ_TLS:-true}"


# Get Candidate DCs
function CandidateDirServ {
  local DNS_SEARCH_STRING

  # Select whether to try to use AD "sites"
  if [[ -n ${ADSITE:-} ]]
  then
    DNS_SEARCH_STRING="_ldap._tcp.${ADSITE}._sites.dc._msdcs.${DIR_DOMAIN}"
  else
    DNS_SEARCH_STRING="_ldap._tcp.dc._msdcs.${DIR_DOMAIN}"
  fi

  # Populate global directory-server array
  mapfile -t DS_LIST < <(
    dig -t SRV "${DNS_SEARCH_STRING}" | \
    sed -e '/^$/d' -e '/;/d' | \
    awk '/\s\s*IN\s\s*SRV\s\s*/{ printf("%s;%s\n",$7,$8) }' | \
    sed -e 's/\.$//'
  )

  if [[ ${#DS_LIST[@]} -eq 0 ]]
  then
    echo "Unable to generate a list of candidate servers"
    return 1
  else
    echo "Found ${#DS_LIST[@]} candidate directory-servers"
    return 0
  fi
}

# Make sure directory-server ports are open
function PingDirServ {
  local    DIR_SERV
  local    DS_NAME
  local    DS_PORT
  local -a GOOD_DS_LIST


  for DIR_SERV in "${DS_LIST[@]}"
  do
    DS_NAME="${DIR_SERV//*;/}"
    DS_PORT="${DIR_SERV//;*/}"

    if [[ $(
        timeout 1 bash -c "echo > /dev/tcp/${DS_NAME}/${DS_PORT}"
      ) -eq 0 ]]
    then
      GOOD_DS_LIST+=("${DIR_SERV}")
      echo "${DIR_SERV//*;} responds to port-ping"
    fi
  done

  if [[ ${#GOOD_DS_LIST[@]} -gt 0 ]]
  then
    # Overwrite global directory-server array with successfully-pinged
    # servers' info
    DS_LIST=("${GOOD_DS_LIST[@]}")
    return 0
  else
    echo "All candidate servers failed port-ping"
    return 1
  fi
}

# Check if directory-servers support TLS
function CheckTLSsupt {
  local    DIR_SERV
  local    DS_NAME
  local    DS_PORT
  local -a GOOD_DS_LIST

  for DIR_SERV in "${DS_LIST[@]}"
  do
    DS_NAME="${DIR_SERV//*;/}"
    DS_PORT="${DIR_SERV//;*/}"

    if [[ $(
        echo | \
        openssl s_client -showcerts -starttls ldap \
          -connect "${DS_NAME}:${DS_PORT}" 2> /dev/null | \
        openssl verify > /dev/null 2>&1
      )$? -eq 0 ]]
    then
      GOOD_DS_LIST+=("${DIR_SERV}")
      echo appending
    fi

    # Add servers with good certs to list
    if [[ ${#GOOD_DS_LIST[@]} -gt 0 ]]
    then
      # Overwrite global directory-server array with successfully-pinged
      # servers' info
      DS_LIST=("${GOOD_DS_LIST[@]}")
      return 0
    else
      # Null the list
      DS_LIST=()
      echo "${DS_NAME} failed cert-check"
    fi
  done
}



################
# Main program #
################

CandidateDirServ
PingDirServ
CheckTLSsupt

echo "${#DS_LIST[@]}"
