#!/bin/bash -u



function errecho () { echo "$*" >&2; }
function fatal() { errecho "FATAL ERROR: $*"; exit 13; }
function error() { errecho "ERROR: *$"; }
function log() { echo "$*"; }

function usage() {
	errecho "usage: "
	errecho "    $0 tcp-activate  <srcPort> <targetIp> <destPort>"
	errecho "    $0 tcp-deactivate  <srcPort> <targetIp> <destPort>"
}

function checkArgsNumber() {
	expectedNb=$1
	shift 
	if [ $# -ne $expectedNb ]; then
		usage
		fatal "Arguments do not match expected arguments count for command ${command}"
	fi
}

function incomingForwardingRule() { echo FORWARD -m state -d ${targetIp} --state NEW,RELATED,ESTABLISHED -j ACCEPT; }
	
function incomingNatRule() { echo PREROUTING -t nat -p tcp --dport ${srcPort} -j DNAT --to ${targetIp}:${destPort} ;}

function installIPTablesRule() {
	if ! ( sudo iptables -C $* 2>/dev/null ) ; then
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



command=${1:-}
shift
case ${command} in

    help | -h | --help | -\?)
        usage
        exit 0
        ;;
    tcp-activate )
		checkArgsNumber 3 $*
		srcPort=$1
		targetIp=$2
		destPort=$3
		installRules 
        exit 0;    
        ;;
    tcp-deactivate )
		checkArgsNumber 3 $*
		srcPort=$1
		targetIp=$2
		destPort=$3
		removeRules 
        exit 0;    
        ;;
    '' )
		usage
		fatal "A command must be provided"
		;;
esac


usage
fatal "Unknown command : '$command' \n"
