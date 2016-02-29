#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

LOG_OPTION=""
CACHE_OPTION=""
FORGE_URL_OPTION=""

if [[ -n ${PUPPET_FORGE_URL} ]]; then
 FORGE_URL_OPTION="-x ${PUPPET_FORGE_URL}"
fi

if [[ -d "/var/cache/puppet-forge-server" ]]; then
	CACHE_OPTION="--cache-basedir /var/cache/puppet-forge-server"
	echo "Using ${CACHE_OPTION}"
fi

if [[ -d "/var/log/puppet-forge-server" ]]; then
	LOG_OPTION="--log-dir /var/log/puppet-forge-server"
	echo "Using ${CACHE_OPTION}"
fi

puppet-forge-server ${FORGE_URL_OPTION} -x http://forge.puppetlabs.com \
 ${CACHE_OPTION} ${LOG_OPTION} --pidfile /tmp/puppet-forge-server.pid
