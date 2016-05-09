#!/bin/bash

# Name: doDeploy.sh
#Execute this shell script to deploy Java projects built by Maven automatically on remote hosts.

# debug option
#_XTRACE_FUNCTIONS=$(set +o | grep xtrace)
#set -o xtrace

# define user friendly messages
header="
Function: Execute this shell script to deploy Java projects built by Maven automatically on remote hosts.
License: Open source software
"

# define variables
# Where to get source code
project_clone_depends_1="ssh://git@xxx/xxx1.git"
project_clone="ssh://git@xxx/xxx.git"
deploy_target_host_ip="xxx.xxx.xxx.xxx"
#project_top_directory_to_target_host="/data/docker/business-service/bs-core-01"
project_top_directory_to_target_host="/path/to/deploy"
# Setting how many days do you want save old releases, default is 10 days
save_old_releases_for_days=10
# end define variables

# pretreatment
project_clone_target_depends_1="`echo ${project_clone_depends_1} | awk -F '[/.]+' '{ print $(NF-1)}'`"
project_clone_target="`echo ${project_clone} | awk -F '[/.]+' '{ print $(NF-1)}'`"
project_clone_repository_name=${project_clone_target}

# end pretreatment

# Public header
# =============================================================================================================================
# resolve links - $0 may be a symbolic link
# learn from apache-tomcat-6.x.xx/bin/catalina.sh
PRG="$0"

while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

# Get standard environment variables
PRGDIR=`dirname "$PRG"`

# echo color function, smarter
function echo_r (){
    #Error, Failed
    [ $# -ne 1 ] && return 1
    echo -e "\033[31m$1\033[0m"
}
function echo_g (){
    # Success
    [ $# -ne 1 ] && return 1
    echo -e "\033[32m$1\033[0m"
}
function echo_y (){
    # Warning
    [ $# -ne 1 ] && return 1
    echo -e "\033[33m$1\033[0m"
}
function echo_b (){
    # Debug
    [ $# -ne 1 ] && return 1
    echo -e "\033[34m$1\033[0m"
}
# end echo color function, smarter

#WORKDIR="$PRGDIR"
#WORKDIR="`realpath ${WORKDIR}`"
WORKDIR="`readlink -f ${PRGDIR}`"

# end public header
# =============================================================================================================================

USER="`id -un`"
LOGNAME="$USER"
if [ $UID -ne 0 ]; then
    echo "WARNING: Running as a non-root user, \"$LOGNAME\". Functionality may be unavailable. Only root can use some commands or options"
fi

command_exists() {
    # which "$@" >/dev/null 2>&1
    command -v "$@" >/dev/null 2>&1
}

check_command_can_be_execute(){
    [ $# -ne 1 ] && return 1
    command_exists $1
}

check_network_connectivity(){
    echo_b "checking network connectivity ... "
    network_address_to_check=8.8.4.4
    stable_network_address_to_check=114.114.114.114
    ping_count=2
    ping -c ${ping_count} ${network_address_to_check} >/dev/null
    retval=$?
    if [ ${retval} -ne 0 ] ; then
        if ping -c ${ping_count} ${stable_network_address_to_check} >/dev/null;then
            echo_g "Network to $stable_network_address_to_check succeed! "
            echo_y "Note: network to $network_address_to_check failed once! maybe just some packages loss."
        elif ! ip route | grep default >/dev/null; then
            echo_r "Network is unreachable, gateway is not set."
            exit 1
        elif ! ping -c2 $(ip route | awk '/default/ {print $3}') >/dev/null; then
            echo_r "Network is unreachable, gateway is unreachable."
            exit 1
        else
            echo_r "Network is blocked! "
            exit 1
        fi
    elif [ ${retval} -eq 0 ]; then
        echo_g "Check network connectivity passed! "
    fi
}

check_name_resolve(){
    echo_b "checking DNS name resolve ... "
    target_name_to_resolve="github.com"
    stable_target_name_to_resolve="www.aliyun.com"
    ping_count=1
    if ! ping  -c${ping_count} ${target_name_to_resolve} >/dev/null; then
        echo_y "Name lookup failed for $target_name_to_resolve with $ping_count times "
        if ping  -c${ping_count} ${stable_target_name_to_resolve} >/dev/null; then
            echo_g "Name lookup success for $stable_target_name_to_resolve with $ping_count times "
        fi
        eval_md5sum_of_nameserver_config="`md5sum /etc/resolv.conf | awk '{ print $1 }'`"
        if test ${eval_md5sum_of_nameserver_config} = "674ea91675cdfac353bffbf49dc593c3"; then
            echo_y "Nameserver config file is validated, but name lookup failed for $target_name_to_resolve with $ping_count times"
            return 0
        fi
        [ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf_$(date +%Y%m%d%H%M%S)~
        cat >/etc/resolv.conf<<eof
nameserver 114.114.114.114
nameserver 8.8.4.4
eof
    check_name_resolve
    else
        echo_g "Check DNS name resolve passed! "
        return 0
    fi
}

function checkOtherDependencies() {
    echo_b "Checking other dependencies for deploy procedure... "

    echo_b "\tChecking user customized variables..."
    # Refer:
    # if [ -z ${var+x} ]; then
    #     echo "var is unset"; else echo "var is set to '$var'"
    # fi
    # if [ "$var x" = " x" ]; then
    #     echo "var is empty"; else echo "var is set to '$var'"
    # fi
    # if [ -z $var ]; then
    #     echo "var is empty"; else echo "var is set to '$var'"
    # fi
    if [[ -z ${project_clone} ]]; then
        echo_r "Error: project_clone is undefined! "
        exit 1
    elif [[ -z ${deploy_target_host_ip} ]]; then
        echo_r "Error: deploy_target_host_ip is undefined! "
        exit 1
    elif [[ -z ${project_top_directory_to_target_host} ]]; then
        echo_r "Error: project_top_directory_to_target_host is undefined! "
        exit 1
    fi
    echo_g "\tChecking user customized variables passed! "

    echo_b "\tChecking disk space available..."
    disk_space_available=`df ${WORKDIR} | tail -n1 | awk '{print $(NF-2)}'`
    if [[ ${disk_space_available} -lt 2097152 ]]; then
        echo_y "Warning: Disk space of $WORKDIR is smaller than 2GB"
        #exit 1
    else
        echo_g "\tChecking disk space available passed! "
    fi

    echo_g "All required dependencies check passed! "

}

function setDirectoryStructureOnLocalHost() {
    if [ -f ${WORKDIR}/.capistrano_ds_lock ];then
        echo_g "Set directory structure has been done, skipping. "
        return
    fi
    echo_b "Setting directory structure... "
    # learn from capistrano
    # Refer: http://capistranorb.com/documentation/getting-started/structure/
    # Refer: http://capistranorb.com/documentation/getting-started/structure/#

    # ├── current -> /var/www/my_app_name/releases/20150120114500/
    # ├── releases
    # │   ├── 20150080072500
    # │   ├── 20150090083000
    # │   ├── 20150100093500
    # │   ├── 20150110104000
    # │   └── 20150120114500
    # ├── repo
    # │   └── <VCS related data>
    # ├── revisions.log
    # └── shared
    #     └── <linked_files and linked_dirs>

    # current is a symlink pointing to the latest release. This symlink is updated at the end of a successful deployment. If the deployment fails in any step the current symlink still points to the old release.
    # releases holds all deployments in a timestamped folder. These folders are the target of the current symlink.
    # repo holds the version control system configured. In case of a git repository the content will be a raw git repository (e.g. objects, refs, etc.).
    # revisions.log is used to log every deploy or rollback. Each entry is timestamped and the executing user (username from local machine) is listed. Depending on your VCS data like branchnames or revision numbers are listed as well.
    # shared contains the linked_files and linked_dirs which are symlinked into each release. This data persists across deployments and releases. It should be used for things like database configuration files and static and persistent user storage handed over from one release to the next.
    # The application is completely contained within the path of :deploy_to. If you plan on deploying multiple applications to the same server, simply choose a different :deploy_to path.

    # Check directories for deploy
    [ ! -d ${WORKDIR}/release ] && mkdir ${WORKDIR}/release
    [ ! -d ${WORKDIR}/repository ] && mkdir ${WORKDIR}/repository
    [ ! -d ${WORKDIR}/share ] && mkdir ${WORKDIR}/share
    # end directories structure
    touch ${WORKDIR}/.capistrano_ds_lock
    echo_g "Set directory structure successfully! "
}

function cleanOldReleases(){
    save_days=${save_old_releases_for_days:-10}
    if [ ! -d ${WORKDIR}/release ]; then
        echo_b "Can NOT find release directory, skipping . "
        return
    fi
    need_clean=$(find ${WORKDIR}/release -mtime +${save_days} -exec ls {} \;)
    if [ ! -z ${need_clean} ]; then
        echo_g "Expired releases found and will be removed from project! "
        find ${WORKDIR}/release -mtime +${save_days} -exec rm -rf {} \;
        if [ $? -eq 0 ]; then
            echo_g "Expired releases have removed from project! "
        else
            echo_r "Can NOT remove expired releases, please alter to Admin users. "
        fi
    else
        echo_g "All releases are not expired, skipping. "
    fi

}

# git_project_clone repository branch
function git_project_clone(){
    set -o errexit
    [ $# -ge 1 ] && project_clone_repository="$1"
    project_clone_repository_name="`echo ${project_clone_repository} | awk -F '[/.]+' '{ print $(NF-1)}'`"
    project_clone_directory=${WORKDIR}/repository/${project_clone_repository_name}
    if test -n $2; then
        branch="$2"
    else
        branch="develop"
    fi
    if test ! -d ${project_clone_directory}; then
        echo_b "git clone from $project_clone_repository"
        git clone ${project_clone_repository} ${project_clone_directory} >>${WORKDIR}/git_$(date +%Y%m%d)_$$.log 2>&1
            # TODO(Guodong Ding) get branch names or revision numbers from VCS data

        cd ${project_clone_directory}
        git checkout ${branch} >>${WORKDIR}/git_$(date +%Y%m%d)_$$.log 2>&1
        cd ..
        echo_g "git clone from $project_clone_repository successfully! "
    else
        echo_b "git pull from $project_clone_repository"
        cd ${project_clone_directory}
        git pull >>${WORKDIR}/git_$(date +%Y%m%d)_$$.log 2>&1
        git checkout ${branch} >>${WORKDIR}/git_$(date +%Y%m%d)_$$.log 2>&1
        # TODO(Guodong Ding) get branch names or revision numbers from VCS data
        cd ..
        echo_g "git pull from $project_clone_repository successfully! "
    fi
    set +o errexit
}

function maven_build_project_deprecated(){
    set -o errexit
    echo_b "Do mvn build java project... "
    check_command_can_be_execute mvn
    [ $# -ge 1 ] && project_clone_repository="$1"
    project_clone_repository_name="`echo ${project_clone_repository} | awk -F '[/.]+' '{ print $(NF-1)}'`"
    project_clone_directory=${WORKDIR}/repository/${project_clone_repository_name}
    cd ${project_clone_directory}
    mvn install >>${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log 2>&1
    mvn clean package >>${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log 2>&1
    cd ..
    echo_g "Do mvn build java project finished with exit code 0! "
    set +o errexit
}

function maven_build_project(){
    echo_b "Do mvn build java project... "
    check_command_can_be_execute mvn
    [ $# -ge 1 ] && project_clone_repository="$1"
    project_clone_repository_name="`echo ${project_clone_repository} | awk -F '[/.]+' '{ print $(NF-1)}'`"
    project_clone_directory=${WORKDIR}/repository/${project_clone_repository_name}

    cd ${project_clone_directory}
    mvn install >>${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log 2>&1
    retval=$?
    if [ ${retval} -ne 0 ] ; then
        echo_r "mvn install failed! More details refer to ${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log"
        exit 1
    else
        echo_g "mvn install successfully! "
    fi

    mvn clean package >>${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log 2>&1
    retval=$?
    if [ ${retval} -ne 0 ] ; then
        echo_r "mvn clean package failed! More details refer to ${WORKDIR}/mvn_build_$(date +%Y%m%d)_$$.log"
        exit 1
    else
        echo_g "mvn clean package successfully! "
    fi
    cd ..
    echo_g "Do mvn build java project finished with exit code 0! "
}

function check_ssh_can_be_connect(){
    [ $# -ne 1 ] && return 1
    echo_b "Check if can ssh to remote host $1 ... "
    check_command_can_be_execute ssh || return 1
    ssh -i /etc/ssh/ssh_host_rsa_key -p 22 -oStrictHostKeyChecking=no root@$1 "uname -a >/dev/null 2>&1"
    retval=$?
    if [ ${retval} -ne 0 ] ; then
        echo_r "Check ssh to remote host $1 failed! "
        exit 1
    else
        echo_g "Check ssh to remote host $1 successfully! "
    fi
}

# ssh_execute_command_on_remote_host hostname command
function ssh_execute_command_on_remote_host(){
    [ $# -ne 2 ] && return 1
    ssh -i /etc/ssh/ssh_host_rsa_key -p 22 -oStrictHostKeyChecking=no root@$1 "$2"
}

# scp_local_files_to_remote_host local_path hostname remote_path
function scp_local_files_to_remote_host(){
    [ $# -ne 3 ] && return 1
    [ ! -d $1 -a ! -f $1 ] && return 1
    check_ssh_can_be_connect $2
    scp -i /etc/ssh/ssh_host_rsa_key -P 22 -oStrictHostKeyChecking=no -rp $1 root@$2:$3 >/dev/null 2>&1
    retval=$?
    if [ ${retval} -ne 0 ] ; then
        echo_r "scp_local_files_to_remote_host failed! "
        exit 1
    else
        echo_g "scp_local_files_to_remote_host successfully! "
    fi

}

function deploy() {
    [ -n "$header" ] && echo "$header"
    # check a directories lock, Note: this is redundant
    if [[ ! -f ${WORKDIR}/.lock ]]; then
        setDirectoryStructureOnLocalHost
    fi
    cleanOldReleases
    # do dependencies checking
    check_network_connectivity
    check_name_resolve
    checkOtherDependencies

    check_ssh_can_be_connect ${deploy_target_host_ip}

    # do core job
    git_project_clone "$project_clone_depends_1"
    git_project_clone "$project_clone"
    maven_build_project "$project_clone_depends_1"
    maven_build_project "$project_clone"
    cd ${WORKDIR}

    # links_target_directory_to_current
    # Make directory to release directory
    if test ! -d ${WORKDIR}/release -o ! -d ${WORKDIR}/share; then
        echo_r "capistrano directory structure is broken, make sure the file .capistrano_ds_lock is deleted before a new deploy! "
        exit 1
#        test -f ${WORKDIR}/.capistrano_ds_lock && \rm -rf  ${WORKDIR}/.capistrano_ds_lock
    fi
    new_release_just_created="$WORKDIR/release/$(date +%Y%m%d%H%M%S)"
    [ ! -d ${new_release_just_created} ] && mkdir ${new_release_just_created}
    [ -d ${WORKDIR}/repository/${project_clone_repository_name}/target/${project_clone_repository_name}/ ] && \
        \cp -rf ${WORKDIR}/repository/${project_clone_repository_name}/target/${project_clone_repository_name}/* ${new_release_just_created}
     # Make source code symbolic link to current
    ( [ -f ${WORKDIR}/current ] || [ -d ${WORKDIR}/current ] ) && rm -rf ${WORKDIR}/current
    ln -s ${new_release_just_created} ${WORKDIR}/current

#    scp_local_files_to_remote_host ${WORKDIR}/current/ ${deploy_target_host_ip} ${project_top_directory_to_target_host}
    saved_IFS=$IFS
    IFS=' '
    cd ${WORKDIR}/current
    for file in ${WORKDIR}/current/*;do
        scp_local_files_to_remote_host ${file} ${deploy_target_host_ip} ${project_top_directory_to_target_host}
    done
    cd ${WORKDIR}
    IFS=${saved_IFS}

    # Move conf and logs directives from release to share
    [ -d ${WORKDIR}/release/conf ] && mv ${WORKDIR}/release/conf ${WORKDIR}/share/conf
    [ -d ${WORKDIR}/release/logs ] && mv ${WORKDIR}/release/logs ${WORKDIR}/share/logs

    # Make conf and logs symbolic link to current
    [ -d ${WORKDIR}/share/conf ] && ln -s ${WORKDIR}/share/conf ${WORKDIR}/current/conf
    [ -d ${WORKDIR}/share/logs ] && ln -s ${WORKDIR}/share/logs ${WORKDIR}/current/logs

    # Start service or validate status
    if [[ -e ${WORKDIR}/current/bin/startup.sh ]]; then
        ${WORKDIR}/current/bin/startup.sh start
        RETVAL=$?
    else
        # TODO(Guodong Ding) external health check
        RETVAL=0
    fi
    RETVAL=$?

    # if started ok, then create a workable program to a file
    if [[ ${RETVAL} -eq 0 ]]; then
    # Note cat with eof must start at row 0, and with eof end only, such as no blank spaces, etc
    cat >${WORKDIR}/share/workable_program.log <<eof
${new_release_just_created}
eof
    echo_g "Deploy successfully! "
    echo_g "current workable version is $(cat ${WORKDIR}/share/workable_program.log)"
#    ls --color=auto -l ${WORKDIR}/current
#    ls --color=auto -l ${WORKDIR}/current/
    else
        echo_r "Error: Deploy failed! "
        $0 rollback
    fi
}

# Rollback to last right configuration
function rollback() {
    [ -n "$header" ] && echo "$header"
    echo_b "Rollback to last right configuration... "
    # The key is find last files which can work
    WORKABLE_PROGRAM=`cat ${WORKDIR}/share/workable_program.log`
    if [[ -z ${WORKABLE_PROGRAM} ]]; then
        echo_r "Error: Can NOT find workable release version! Please check if it is first deployment! "
        exit 1
    fi
    # Stop service if we have
    if [[ -e ${WORKDIR}/current/bin/startup.sh ]]; then
        ${WORKDIR}/current/bin/startup.sh stop
    fi

    # Remove failed deploy
    rm -rf ${WORKDIR}/current

    # Remake source code symbolic link to current
    ln -s ${WORKABLE_PROGRAM} ${WORKDIR}/current

    # Remake conf and logs symbolic link to current
    [ -d ${WORKDIR}/share/conf ] && ln -s ${WORKDIR}/share/conf ${WORKDIR}/current
    [ -d ${WORKDIR}/share/logs ] && ln -s ${WORKDIR}/share/logs ${WORKDIR}/current

    # Start service or validate status
    if [[ -e ${WORKDIR}/current/bin/startup.sh ]]; then
        ${WORKDIR}/current/bin/startup.sh start
        RETVAL=$?
    else
        # TODO(Guodong Ding) external health check
        RETVAL=0
    fi
    RETVAL=$?

    # if started ok, then create a workable program to a file
    if [[ ${RETVAL} -eq 0 ]]; then
        echo_g "Rollback successfully! "
        echo_g "current workable version is $WORKABLE_PROGRAM"
#        ls --color=auto -l ${WORKDIR}/current
    fi
}

function destroy() {
    [ -n "$header" ] && echo "$header"
    # echo a Warning message
    echo_y "Warning: This action will destroy all this project, and this is unrecoverable! "
    answer="n"
    echo_y "Do you want to destroy this project? "
    read -p "(Default no,if you want please input: y ,if not please press the enter button):" answer
    case "$answer" in
        y|Y|Yes|YES|yes|yES|yEs|YeS|yeS )
        # delete all file expect for this script self
        # find: warning: Unix filenames usually don't contain slashes (though pathnames do).  That means that '-name `./deploy.sh'' will probably evaluate to false all the time on this system.  You might find the '-wholename' test more useful, or perhaps '-samefile'.  Alternatively, if you are using GNU grep, you could use 'find ... -print0 | grep -FzZ `./deploy.sh''.
            # echo $WORKDIR/
            #find -L $WORKDIR -type f ! -name "$(basename $0)" -exec ls --color=auto -al {} \;
            # find -L . -type f ! -name "deploy.sh" -exec ls --color=auto -al {} \;
            # find -L . -type d -exec ls --color=auto -al {} \;
            # find -L ./ -maxdepth 1 ! -name "deploy.sh" ! -wholename "./"
        # ls | grep -v "filename" | xargs rm -rf
        find -L ${WORKDIR} -maxdepth 1 ! -name "$(basename $0)" ! -wholename "$WORKDIR"  -exec rm -rf {} \;
        if [ $? -eq 0 ];then
            test -f ${WORKDIR}/.capistrano_ds_lock && \rm -rf  ${WORKDIR}/.capistrano_ds_lock
            echo_g "Destroy this project successfully! Now will exit with status 0. "
            exit 0
        else
            echo_r "Error: something go wrong! Please check or alter to Admin user! "
            exit 1
        fi
        ;;
        n|N|No|NO|no|nO)
        echo_g "destroy action is cancel"
        exit 0
        ;;
        *)
        echo_r "Are you kidding me? You are a bad kid! "
        exit 1
        ;;
    esac

}


function main(){
    lock_filename="lock_$$_$RANDOM"
#    lock_filename_full_path="/var/lock/subsys/$lock_filename"
    lock_filename_full_path="/var/lock/$lock_filename"
    if ( set -o noclobber; echo "$$" > "$lock_filename_full_path") 2> /dev/null;then
        trap 'rm -f "$lock_filename_full_path"; exit $?' INT TERM EXIT
        # Just a test for call itself, comment it
         if [[ $# -ne 1 ]]; then
#            $0 deploy
            [ ! -x ${WORKDIR}/`basename $0` ] && chmod +x ${WORKDIR}/`basename $0`
            ${WORKDIR}/`basename $0` deploy
            exit 0
         fi
        case $1 in
            deploy)
                deploy
                ;;
            rollback)
                rollback
                ;;
            destroy)
                destroy
                ;;
            help|*)
                echo "Usage: $0 {deploy|rollback|destroy} with $0 itself"
                exit 1
                ;;
        esac

        rm -f "$lock_filename_full_path"
        trap - INT TERM EXIT
    else
        echo "Failed to acquire lock: $lock_filename_full_path"
        echo "held by $(cat ${lock_filename_full_path})"
fi

}

main $@

# debug option
#${_XTRACE_FUNCTIONS}
