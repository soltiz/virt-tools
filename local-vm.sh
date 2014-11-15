#!/bin/bash -u


allowed_vmnums="0 1 2 3 4 5 6"

TOOLS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"



vmTemplateDisk="${TOOLS_DIR}/local-template.qcow2"
#rootPart=/dev/rootvg/rootlv
rootPart=/dev/sda1
instancesDir="/data/vms"

ips[0]="192.168.122.10"
ips[1]="192.168.122.11"
ips[2]="192.168.122.12"
ips[3]="192.168.122.13"
ips[4]="192.168.122.14"
ips[5]="192.168.123.15"
ips[6]="192.168.123.16"

gatewayIps[0]="192.168.122.1"
gatewayIps[1]="192.168.122.1"
gatewayIps[2]="192.168.122.1"
gatewayIps[3]="192.168.122.1"
gatewayIps[4]="192.168.122.1"
gatewayIps[5]="192.168.123.1"
gatewayIps[6]="192.168.123.1"

bridges[0]="virbr0"
bridges[1]="virbr0"
bridges[2]="virbr0"
bridges[3]="virbr0"
bridges[4]="virbr0"
bridges[5]="virbr1"
bridges[6]="virbr1"
vmNetMask=255.255.255.0
dnsDomain=localdomain

ram=512
vcpus=1

function errecho() {
 echo "$*" >&2
}

function error() {
	errecho "ERROR: $*"
}

function fatal() {
	errecho "FATAL ERROR: $*"
	exit 42
}


function logger() {
 if [ "${quiet:-}" == "true" ] ; then
	cat >> /dev/null
 else 
    cat
 fi
}

function log() {
	 echo " " | logger
	 echo "  $*" | logger
	 echo " " | logger
}


function create-ubuntu-img() {
	generationDir="$(mktemp -d)"

	sudo ubuntu-vm-builder kvm trusty \
                  --domain=newvm \
                  --destdir ${generationDir} \
                  --bridge=virbr0 \
                  --hostname=localvm0 \
                  --mem=256\
                  --ip=192.168.122.10 \
                  --mask=${vmNetMask} \
                  --components main,universe \
                  --addpkg=acpid \
                  --addpkg=linux-image-generic \
                  --addpkg=vim \
                  --addpkg=openssh-server \
                  --addpkg=avahi-daemon \
                  --libvirt=qemu:///system \
                  && sudo mv ${generationDir}/*.qcow2 "${vmTemplateDisk}"
    sudo rm -rf "${generationDir}"
}


function print-usage() {
	errecho "Usage: ${0} [-f] [-q] <VmNum>"
        errecho  "This command will create a new clean copy of hard drive (except for Vm#0) and start the localvm<VmNum> host" 
	errecho "Supported vmNums are (WARNING : vm #0 will use and change base image for all others !)"
	for vmnum in ${allowed_vmnums}
	do
		errecho "  ${vmnum} ==> associated automatically to IP ${ips[${vmnum}]}"
	done
    errecho "-f flag is required to owerwrite a running vm (which will stop running VM, then destroy its disk)"
    errecho "-q flag removes all logs and normal messages"
    errecho "-k flag keeps existing disk"
}

if ! ( sudo ls / >> /dev/null )
then
 error "Must have sudo rights..."
 exit 18
fi

if [ ! -f "${vmTemplateDisk}" ]; then
	fatal "Template image ""${vmTemplateDisk}"" does not exist. run $0 --createTemplate to initialize one"
fi

if [ "${1:-}" == "--createTemplate" ] ; then
	create-ubuntu-img || fatal "image creation failed"
	log "Image creation succeeded."
	exit 0
fi

force=false
quiet=false
k1disk=false
keep=false
while [ "$#" -gt 1 ]
do
	case "$1" in
		"-f")
			force=true
			;;
		"-k")
			keep=true
			;;
		"-q")
			quiet=true
			;;
		*)
			print-usage
			exit 33
	esac
    shift
done

if [ "$#" != 1 ]
then
	print-usage
	exit 34
fi

vmnum=${1}
regexp=".*\<${1}\>.*"
if ! [[  ${allowed_vmnums} =~  ${regexp} ]]
then
 error "Unknown lmc ivq vm number '${vmnum}'."
 print-usage
 exit 2
fi



function defineAndStart() {
 hostname="$1"
 diskFile="$2"
 bridge="$3"
 log "Starting vm '${hostname}' with diskFile '${diskFile}' ..."
   sudo virt-install -q --connect=qemu:///system --network=bridge:$bridge --disk path="${diskFile}",format=qcow2 --check-cpu --hvm --ram ${ram} --vcpus=${vcpus} --name="${hostname}" --import --graphics vnc,keymap=fr --noautoconsole | logger
 }

function vmStatus() {
 hostname="$1"
 status=$(sudo virsh domstate ${hostname} 2>/dev/null)
 if [ "$status" == "" ] 
 then
  echo "undefined"
 else 
  echo "$status"
 fi
}

function createVmDiskFile () {
 targetDiskFile="$1"
 hostname="$2"
 vmIp="$3"
 gatewayIp="$4"
 dnsServers=${gatewayIp}
 log "creating new disk file '${targetDiskFile}' with inbuilt static IP '${vmIp}' ..." 
 sudo rm -f "${targetDiskFile}"
 sudo qemu-img create -b "${vmTemplateDisk}" -f qcow2 "${targetDiskFile}" | logger
 log "customization of IP and hostname in disk file..."
 tmpInterfaces=$(mktemp)
 tmpInterface=$(mktemp)
 cat > ${tmpInterfaces} << ENDOFFILE
 auto lo
 iface lo inet loopback
 source /etc/network/interfaces.d/*.cfg
ENDOFFILE

 cat > ${tmpInterface} << ENDOFFILE
 auto eth0
 iface eth0 inet static
 	address ${vmIp}
 	netmask ${vmNetMask}
 	gateway ${gatewayIp} 
 	dns-nameservers ${dnsServers}
 	dns-search ${dnsDomain}
ENDOFFILE
 tmpHostname=$(mktemp)
 tmpHosts=$(mktemp)
 echo -n "${hostname}" > "${tmpHostname}"
 sudo guestfish --rw -a "${targetDiskFile}"   << ENDGUESTFISH
run
mount ${rootPart} /
upload "${tmpHostname}" /etc/hostname
upload "${tmpInterfaces}" /etc/network/interfaces
upload "${tmpInterface}" /etc/network/interfaces.d/eth0.cfg
download "/etc/hosts" "${tmpHosts}"
!sed -i 's/.*aptcache.*/${gatewayIp} aptcache/g' "${tmpHosts}"
upload "${tmpHosts}" /etc/hosts
quit
ENDGUESTFISH

sudo rm -rf "${tmpHostname}" "${tmpInterface}" "${tmpInterfaces}" "${tmpHosts}"
} 

function stopVm () {
 domain="${1}"
 log "Stopping libvirt domain '${domain}'..."
 sudo virsh destroy "${domain}" | logger
}

function startVm () {
 domain="${1}"
 log "Starting libvirt domain '${domain}'..."
 sudo virsh start "${domain}" | logger
}

function requestConfirmOrFail() {
 message="${1}"
 if [ "${force}" != "true" ]
 then
	 echo -n "${message} (y/N) : " 2>&1
	 read answer
	 if ! [[ "${answer}" =~ [yY] ]]
	 then
	   error "Cancelled by user"
	   exit 4
	 fi
 fi
}



vmHostname="localvm${vmnum}"

if [ ${vmnum} -eq 0 ] ; then
 	vmDiskFile="${vmTemplateDisk}"
else
	vmDiskFile="${instancesDir}/${vmHostname}.qcow2"
fi


vmIp="${ips[vmnum]}"
gatewayIp="${gatewayIps[vmnum]}"
bridge="${bridges[vmnum]}"

status="$(vmStatus ${vmHostname})"
case "${status}" in
	"undefined")
		log "Vm '${vmHostname}' is undefined in virsh."
		if [ ${vmnum} -ne 0 ]; then
			if [ -f "${vmDiskFile}" ] && [ $keep != true ]
			then
				if [ "${force}" != "true" ]
				then
					requestConfirmOrFail "Disk file '${vmDiskFile}' already exists. Do you confirm destruction of disk content ? "
				fi
			fi
			if [ $keep != true ]; then
				createVmDiskFile "${vmDiskFile}" "${vmHostname}" "${vmIp}" "${gatewayIp}"
			fi
		fi
		defineAndStart ${vmHostname} ${vmDiskFile} ${bridge}
		;;

	"shut off" | "fermé")
		log "Vm '${vmHostname}' already exists, although currently shut off."
		if [ ${vmnum} -ne 0 ] && [ $keep != true ]; then
			requestConfirmOrFail "Do you confirm disk destruction of vm '${vmHostname}' ?"		
			createVmDiskFile "${vmDiskFile}" "${vmHostname}" "${vmIp}" "${gatewayIp}"
		fi
		startVm "${vmHostname}"
        ;;

	"running" | "en cours d'exécution" )
		log "Vm '${vmHostname}' is running."
		if [ ${vmnum} -eq 0 ] || [ $keep == true ]; then
			exit 0
		fi
		requestConfirmOrFail "Do you confirm stop and disk destruction of vm '${vmHostname}' ?"
        stopVm "${vmHostname}"
		createVmDiskFile "${vmDiskFile}" "${vmHostname}" "${vmIp}" "${gatewayIp}"
		startVm "${vmHostname}"
		;;

    *)
		error "Unknown vm status ${status} for vm '${vmHostname}'."
		exit 8
esac
		
	  
