#!/bin/bash
#
# Script the rollout of Fuel-Devops installation for a given Fuel version
#
set -e

installRequirements() {
  # setup base
  sudo apt-get install --yes \
      git \
      libyaml-dev \
      libffi-dev \
      python-dev \
      python-pip \
      qemu \
      libvirt-bin \
      libvirt-dev \
      vlan \
      bridge-utils \
      genisoimage \
      libvirt-bin

  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt-get install --yes python-virtualenv libpq-dev libgmp-dev pkg-config
  sudo pip install pip virtualenv --upgrade
  hash -r
}

setupFuelDevops() {
  # setup fuel devops
  cd $WORKING_DIR
  virtualenv --no-site-packages fuel-devops-venv
  . fuel-devops-venv/bin/activate
  pip install git+https://github.com/openstack/fuel-devops.git@master \
    --upgrade
}

setupVirshPool() {
  # setup virsh storage
  virsh="virsh -c $libVirtUR"
  virsh pool-info $storagePool
  if [ "$?" != "0" ]; then
    virsh pool-define-as --type=dir --name=$storagePool \
      --target=$storagePoolLoc
    virsh pool-autostart $storagePool
    virsh pool-start $storagePool
    # chgrp libvirt $storagePoolLoc
    # chmod 775 $storagePoolLoc
  fi
  set +e
  virsh pool-start $storagePool
  set -e
}

editGroups() {
  id | egrep "sudo.*libvirtd"
  if [ "$?" != "0" ]; then
    me=$(whoami)
    sudo usermod $me -a -G libvirtd,sudo
  fi
}

exportDB() {
  db=$1
  ver=$2
  if [ "$db" == "sqlite" ]; then
    export DEVOPS_DB_NAME=$WORKING_DIR/fuel-devops-$ver
    export DEVOPS_DB_ENGINE="django.db.backends.sqlite3"
  fi
}

setupDB() {
  db=$1
  ver=$2
  if [ "$db" == "postgres" ]; then
    # setup postgresql
    sudo apt-get install --yes postgresql
    pg_version=$(dpkg-query --show --showformat='${version;3}' postgresql)
    pg_createcluster $pg_version main --start
    sudo sed -ir 's/peer/trust/' /etc/postgresql/9.*/main/pg_hba.conf
    sudo service postgresql restart
    sudo -u postgres psql -c \
      "CREATE ROLE fuel_devops WITH LOGIN PASSWORD 'fuel_devops'"
    sudo -u postgres createdb fuel_devops-$ver -O fuel_devops-$ver
  elif [ "$db" == "sqlite" ]; then
    sudo apt-get install --yes libsqlite3-0
    exportDB $db $ver
  else
    echo "Database $db not supported!"
    exit 1
  fi
  django-admin.py syncdb --settings=devops.settings
  django-admin.py migrate devops --settings=devops.settings
}

setupKVM() {
  if [ -e "/etc/modprobe.d/qemu-system-x86.conf" ]; then
      grep "nested=1" /etc/modprobe.d/qemu-system-x86.conf
      if [ "$?" != "0" ]; then
          sudo sh -c \
            'echo "options kvm_intel nested=1" >> \
            /etc/modprobe.d/qemu-system-x86.conf'
      fi
  else
      sudo sh -c \
        'echo "options kvm_intel nested=1" >> \
        /etc/modprobe.d/qemu-system-x86.conf'
  fi
  sudo apt-get install --yes cpu-checker
  sudo modprobe kvm_intel
  sudo kvm-ok
  if [ "$?" != "0" ]; then
      exit 1
  fi
  nested=$(cat /sys/module/kvm_intel/parameters/nested)
  if [ "$nested" != "Y" ]; then
      echo "no nesting..."
  fi
}

setupFuelQA() {
  version=$1
  requirements="fuelweb_test/requirements.txt"
  if [ ! -d "$WORKING_DIR/fuel-qa" ]; then
    git clone https://github.com/openstack/fuel-qa
  fi
  cd $WORKING_DIR/fuel-qa
  git reset --hard
  git clean  -d  -fx ""
  branch=$(git branch | grep ^\* | awk '{ print $2 }')
  if [ "$branch" != "stable/$fuelVersion" ];then
    if [ "$fuelVersion" == "7.0" ]; then
      git checkout stable/$fuelVersion
      # perl -pi.org -e '/glanceclient>=/glanceclient==/' $requirements
      # perl -pi.org -e '/keystoneclient>=/keystoneclient==/' $requirements
      # perl -pi.org -e '/novaclient>=/novaclient==/' $requirements
      # perl -pi.org -e '/neutronclient>=2.0/neutronclient==2.2.6/' $requirements
    elif [ "$fuelVersion" == "9.0" ]; then
      git checkout master
    fi
    pip install -r ./$requirements --upgrade
    # https://bugs.launchpad.net/oslo.service/+bug/1525992
    if [ "$fuelVersion" == "9.0" ]; then
        pip install oslo.i18n --upgrade
    fi
  fi
  django-admin.py syncdb --settings=devops.settings
  django-admin.py migrate devops --settings=devops.settings
}

validateAndSetOptions() {
  export WORKING_DIR=$workDir
  if [ ! -d "$WORKING_DIR" ]; then
    mkdir $WORKING_DIR
  fi
  if [ "$database" != "postgres" ] && [ "$database" != "sqlite" ]; then
    usage
    echo "Unsuported database: $database."
    exit 1
  elif [ "$fuelVersion" != "9.0" ] && [ "$fuelVersion" != "8.0" ]; then
    usage
    echo "Unsupported Fuel version: $fuelVersion"
    exit 1
  fi
  if [ -z "$iso" ]; then
    iso="$WORKING_DIR/$isoname-$fuelVersion.iso"
  fi
  if [ -e "$iso" ]; then
    export ISO_PATH=$iso
  elif [ -e "$WORKING_DIR/$iso"]; then
    export ISO_PATH=$WORKING_DIR/$iso
  else
    usage
    echo "ISO $iso does not exist, neither in $WORKING_DIR ?"
    exit 1
  fi
  export LIBVIRT_DEFAULT_URI=$libVirtURL
  export NODES_COUNT=6
  export ENV_NAME=fuel_system_test
  if [ "$fuelVersion" != "7.0" ]; then
    export ENV_NAME=fuel_system_test-$fuelVersion
  fi

  export VENV_PATH=$WORKING_DIR/fuel-devops-venv
  # bug in libvirt with resume that can't change the cpu
  #
  if [ "$fuelVersion" == "9.0" ]; then
    export SNAPSHOTS_EXTERNAL=false
  else
    export SNAPSHOTS_EXTERNAL=true
  fi
  # fuck da fuck, missing from the documentation!!!
  export ISO_MIRANTIS_FEATURE_GROUP=true
}

# maybe also check group=libvirtd
libvirtPermissionFix() {
  set +e
  sudo chown root:libvirtd $storagePoolLoc
  sudo chmod 775 $storagePoolLoc
  ls $storagePoolLoc | grep fuel_
  if [ "$?" == "0" ]; then
    sudo chown root:libvirtd $storagePoolLoc/fuel_*
    sudo chmod 660 $storagePoolLoc/fuel_*
  fi
  virsh pool-refresh $storagePool
  set -e
}

cleanVirtStorage() {
  set +e
  disks=$(virsh vol-list $storagePool | grep fuel_system_test | \
    awk '{ print $1 }' | egrep -v "\-\-|Name")
  vmc=$(virsh list --all | grep fuel_system_test | awk ' { print $2 }' | \
    egrep -v "Name|^$" | wc -l)
  if [ "$vmc" == "0" ]; then
    for disk in $disks; do
      virsh vol-delete $disk --pool $storagePool
    done
  fi
  set -e
}

copyInSettingsFile() {
  file=$1
  if [ -e "$file" ]; then
    cp $file $WORKING_DIR/fuel-qa/fuelweb_test/settings.py
  fi
}

showQaTestList() {
  if [ -z "$WORKING_DIR" ]; then
    usage
    echo "Please specify a workdir!!"
    exit 1
  fi
  cd $WORKING_DIR/fuel-qa
  find . -type f | xargs grep ^\@test | grep -v html | \
    awk -F\: '{ print $2 }' | sort | uniq
}

fuelVersion=""
database="sqlite"
libVirtURL="qemu:///system"
remoteVirt=""
iso=""
isoname="MirantisOpenStack"
workDir="$HOME/working_dir"
settingsFile=""
origPwd=$PWD
list=""
scriptMode=""
storagePool="default"
storagePoolLoc="/var/lib/libvirt/images"
usage() {
  echo "$0:
    -h|--help           this!
    -v|--version        Version of the Fuel image, 7.0 or 8.0
    -d|--database       database to use, sqlite or postgres ($database)
    -i|--iso            Fuel ISO file to use ($iso)
    -w|--workdir        Directory to work from ($workDir)
    -s|--settings       Settings file to copy in
    -L|--list           Show QA test list
    -S|--script         Script + options to daisy chain after preperations.
    -l|--virturl        Libvirt URL e.g. qemu+ssh://nibbler/system ($libVirtURL)"
}

set -- `getopt -u -o "S:l:Lhv:d::i:w:s:" \
  --longoptions="script:,version:,database:,help,iso:,libvirturl:,workdir:,settings:,list,"  "h" "$@"` || usage

while [ $# -gt 0 ]
do
  case "$1" in
    --version|-v)
      fuelVersion=$2
      shift
    ;;
    --database|-d)
      database=$2
      shift
    ;;
    --iso|-i)
      iso=$2
      shift
    ;;
    --libvirturl|-l)
      libVirtURL=$2
      remoteVirt=1
      export CONNECTION_STRING=$libVirtURL
      shift
    ;;
    --workdir|-w)
      workDir=$2
      shift
    ;;
    --settings|-s)
      settingsFile=`readlink -f $2`
      shift
    ;;
    --script|-S)
      shift
      scriptMode=$( echo $@ | sed -e s/' -- h'//)
    ;;
    --list|-L)
      list=1
    ;;
    --help|-h)
      usage
      exit 1
    ;;
  esac
  shift
done

workDir=$workDir
validateAndSetOptions
setupVirshPool
if [ "$remoteVirt" != "1" ]; then
  libvirtPermissionFix
  # cleanVirtStorage
fi
if [ -d "$WORKING_DIR/fuel-devops-venv" ]; then
  cd $WORKING_DIR
  . fuel-devops-venv/bin/activate
  exportDB $database $fuelVersion
  setupFuelQA
  copyInSettingsFile $settingsFile
else
  mkdir -p $workDir
  cd $WORKING_DIR
  if [ "$remoteVirt" != "1" ]; then
    installRequirements
    editGroups
    setupKVM
  fi
  setupFuelDevops $fuelVersion
  setupDB $database $fuelVersion
  setupFuelQA
  copyInSettingsFile $settingsFile
fi
if [ "$list" == "1" ]; then
  showQaTestList
  exit
fi

if [ "$scriptMode" == "" ]; then
    export PROMPT_COMMAND="echo -n '(fuel_qa_venv:$fuelVersion) '"
    echo "Fuel-DevOps env prepared for Fuel $fuelVersion."
    echo "cd $WORKING_DIR/fuel-qa and run the following to start testing: "
    exec bash
else
    export PROMPT_COMMAND="echo -n '(fuel_qa_venv:S:$fuelVersion)'"
    cd $origPwd
    exec $scriptMode
fi
