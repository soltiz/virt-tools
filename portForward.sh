#!/bin/bash -u



function errecho () { echo "$*" >&2; }
function fatal() { errecho "FATAL ERROR: $*"; exit 13; }
function error() { errecho "ERROR: *$"; }
function log() { echo "$*"; }
function errlogger() { cat >&2 ;}
function logger() { cat ;}

function usage() {
	errecho "usage: "
	errecho "    $0 activate  tcp|udp <srcPort> <privateIp> <destPort>"
	errecho "    $0 deactivate  tcp|udp <srcPort> <privateIp> <destPort>"
	errecho "    $0 list <privateIp>"
}

localIp=172.23.4.49
echo "Local IP is $localIp. (otherwise edit script)"
function checkArgsNumber() {
	expectedNb=$1
	shift 
	if [ $# -ne $expectedNb ]; then
		usage
		fatal "Arguments do not match expected arguments count for command ${command}"
	fi
}
function incomingForwardingRule() { echo FORWARD -m state -d ${localIp} -p ${protocol} --dport ${srcPort} --state NEW,RELATED,ESTABLISHED -j ACCEPT; }
	
function incomingNatRule() { echo PREROUTING -t nat -d ${localIp} -p ${protocol} --dport ${srcPort} -j DNAT --to ${targetIp}:${destPort} ;}

function installIPTablesRule() {
	if ! ( sudo iptables -C $* 2>/dev/null ) ; then
		echo iptables -I $*
		sudo iptables -I $*
	fi
}

function removeIPTablesRule() {
	if  ( sudo iptables -C $* 2>/dev/null ) ; then
		sudo iptables -D $*
	fi
}

removeRules() {
	removeIPTablesRule $(incomingForwardingRule)
	removeIPTablesRule $(incomingNatRule)
}


installRules() {
	installIPTablesRule $(incomingForwardingRule)
	installIPTablesRule $(incomingNatRule)
}

listRedirections() {
	sudo iptables -t nat --list PREROUTING | sed -n "s/^DNAT\s\+\b\([a-z]\+\)\b.*dpt:\([-a-zA-Z0-9]\+\)\b\s\+.*\bto:${targetIp}:\([0-9]\+\).*/\1 ${localIp} : \2  ===>  ${targetIp} : \3/p" 
}


command=${1:-}
shift
case ${command} in

    help | -h | --help | -\?)
        usage
        exit 0
        ;;
    activate )
		checkArgsNumber 4 $*
		protocol=$1
		srcPort=$2
		targetIp=$3
		destPort=$4
		installRules 
		log "Installed redirections for private address '${targetIp}' :"
		listRedirections | logger
        exit $?;    
        ;;
    deactivate )
		checkArgsNumber 4 $*
		protocol=$1
		srcPort=$2
		targetIp=$3
		destPort=$4
		removeRules
		log "Remaining redirections for private address '${targetIp}' :"
		listRedirections | logger
   
        exit $?;    
        ;;
    list )
		checkArgsNumber 1 $*
		targetIp=$1
		listRedirections
		exit $?;
		;;
    '' )
		usage
		fatal "A command must be provided"
		;;
esac


usage
fatal "Unknown command : '$command' \n"
