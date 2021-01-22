#!/usr/bin/env bash

# ----------------------------------------------------------------------------
#
# Functions to:
#  - Download/install kibana x86_64 or aarch64 and where applicable test packages:
#    .zip, .tar.gz, deb, rpm, docker and environments on-prem, cloud or visual
#  - Download/install node and yarn based on kibana supported version
#  - Kibana bootstrap
#  - Run Kibana tests: unit, basic functional, default functional
#  - Logging functions
#
# Author: Liza Dayoub
#
# ----------------------------------------------------------------------------

###
### Since the Jenkins logging output collector doesn't look like a TTY
### Node/Chalk and other color libs disable their color output. But Jenkins
### can handle color fine, so this forces https://github.com/chalk/supports-color
### to enable color support in Chalk and other related modules.
###
export FORCE_COLOR=1

NC='\033[0m' # No Color
WHITE='\033[1;37m'
BLACK='\033[0;30m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
RED='\033[0;31m'
LIGHT_RED='\033[1;31m'
PURPLE='\033[0;35m'
LIGHT_PURPLE='\033[1;35m'
BROWN='\033[0;33m'
YELLOW='\033[1;33m'
GRAY='\033[0;30m'
LIGHT_GRAY='\033[0;37m'

if [ -z $COLOR_LOGS ] || ([ ! -z $COLOR_LOGS ] && $COLOR_LOGS); then
    export COLOR_LOGS=true
fi

Glb_Cache_Dir="${CACHE_DIR:-"$HOME/.kibana"}"
readonly Glb_Cache_Dir

# For static Jenkins nodes
Glb_KbnBootStrapped="no"
Glb_KbnClean="no"

Glb_KbnSkipUbi="no"
readonly Glb_KbnSkipUbi

# *****************************************************************************
# SECTION: Logging functions
# *****************************************************************************

# ----------------------------------------------------------------------------
# Method to get date timestamp
# ----------------------------------------------------------------------------
function date_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

# ----------------------------------------------------------------------------
# Method to print error message
# ----------------------------------------------------------------------------
function echo_error() {
  if [ ${COLOR_LOGS} == true ]; then
    echo -e ${RED}"["$(date_timestamp)"] [ERROR] $1" ${NC}
  else
    echo -e "["$(date_timestamp)"] [ERROR] $1"
  fi
}

# ----------------------------------------------------------------------------
# Method to print error message and exit with error status
# -----------------------------------------------------------------------------
function echo_error_exit() {
  echo_error "$1"
  exit 1
}

# ----------------------------------------------------------------------------
# Method to print warning message
# ----------------------------------------------------------------------------
function echo_warning() {
  if [ ${COLOR_LOGS} == true ]; then
    echo -e ${YELLOW}"["$(date_timestamp)"] [WARNING] $1" ${NC}
  else
    echo -e "["$(date_timestamp)"] [WARNING] $1"
  fi
}

# ----------------------------------------------------------------------------
# Method to print info message
# ----------------------------------------------------------------------------
function echo_info() {
  if [ ${COLOR_LOGS} == true ]; then
    echo -e ${LIGHT_BLUE}"["$(date_timestamp)"] [INFO] $1" ${NC}
  else
    echo -e "["$(date_timestamp)"] [INFO] $1"
  fi
}

# ----------------------------------------------------------------------------
# Method to print debug message
# ----------------------------------------------------------------------------
function echo_debug() {
  if [ ${COLOR_LOGS} == true ]; then
    echo -e ${GRAY}"["$(date_timestamp)"] [DEBUG] $1" ${NC}
  else
    echo -e "["$(date_timestamp)"] [DEBUG] $1"
  fi
}

# ----------------------------------------------------------------------------
# Method to exit script
# ----------------------------------------------------------------------------
function exit_script() {
  rc=${1:-0}
  shift
  msg=$@

  if [ $rc -ne 0 ]; then
    echo_error_exit "$msg"
  fi
  exit
}

# ----------------------------------------------------------------------------
# Method to exit script
# ----------------------------------------------------------------------------
function check_status_ok() {
    [[ "${*}" =~ ^(0 )*0$ ]]
    return
}

# ****************************************************************************
# SECTION: Kibana CI setup functions
# ****************************************************************************

# ----------------------------------------------------------------------------
# Method to create build install directory
# ----------------------------------------------------------------------------
function create_install_dir() {
  if [ ! -z $Glb_Install_Dir ]; then
    return
  fi
  Glb_Install_Dir="$(pwd)/../builds"
  mkdir -p "$Glb_Install_Dir"
  readonly Glb_Install_Dir
}

# ----------------------------------------------------------------------------
# Method to remove build install directory
# ----------------------------------------------------------------------------
function remove_install_dir() {
  if [ ! -d $Glb_Install_Dir ]; then
    return
  fi
  rm -rf "$Glb_Install_Dir"
}

# ----------------------------------------------------------------------------
# Method to remove es build install directory created by Kibana FTR
# ----------------------------------------------------------------------------
function remove_es_install_dir() {
  local esdir="$(pwd)/.es"

  if [ ! -d $esdir ]; then
    return
  fi
  rm -rf $esdir
}

# ----------------------------------------------------------------------------
# Method to remove node_modules directory
# ----------------------------------------------------------------------------
function remove_node_modules_dir() {
  local dir="$(pwd)/node_modules"

  if [ ! -d $dir ]; then
    return
  fi
  rm -rf $dir
}

# ----------------------------------------------------------------------------
# Method to get build server: snapshots
# ----------------------------------------------------------------------------
function get_build_server() {
  if [ ! -z $Glb_Build_Server ]; then
    return
  fi
  Glb_Build_Server="${TEST_BUILD_SERVER:-"snapshots"}"
  if ! [[ "$Glb_Build_Server" =~ ^(snapshots)$ ]] &&
     ! [[ "$Glb_Build_Server" =~ ^(staging)$ ]]; then
    echo_error_exit "Invalid build server: $Glb_Build_Server"
  fi
  if [[ "$Glb_Build_Server" == "staging" ]]; then
    if [[ -z "$ESTF_BUILD_ID" ]]; then
      echo_error_exit "ESTF_BUILD_ID must be populated!"
    fi
  fi
  readonly Glb_Build_Server
}

# ----------------------------------------------------------------------------
# Method to get version from Kibana package.json file
# ----------------------------------------------------------------------------
function get_version() {
  if [ ! -z $Glb_Kibana_Version ]; then
    return
  fi
  local _pkgVersion=$(cat package.json | \
                      grep "\"version\"" | \
                      cut -d ':' -f 2 | \
                      tr -d ",\"\ +" | \
                      xargs)

  Glb_Kibana_Version=${TEST_KIBANA_VERSION:-${_pkgVersion}}

  if [[ -z "$Glb_Kibana_Version" ]]; then
    echo_error_exit "Kibana version can't be empty"
  fi

  if [[ "$Glb_Build_Server" == "snapshots" ]]; then
    Glb_Kibana_Version="${Glb_Kibana_Version}-SNAPSHOT"
  fi

  readonly Glb_Kibana_Version
}

# ----------------------------------------------------------------------------
# Method to get branch from Kibana package.json file
# ----------------------------------------------------------------------------
function get_branch() {
  if [ ! -z $Glb_Kibana_Branch ]; then
    return
  fi
  Glb_Kibana_Branch="$(cat package.json | \
                      grep "\"branch\"" | \
                      cut -d ':' -f 2 | \
                      tr -d ",\"\ +" | \
                      xargs)"

  readonly Glb_Kibana_Branch
}

# ----------------------------------------------------------------------------
# Method to get OS
# ----------------------------------------------------------------------------
function get_os() {
  if [ ! -z $Glb_OS ]; then
    return
  fi
  local _uname=$(uname)
  if [[ ! -z $ESTF_TEST_PACKAGE ]] && [ "$ESTF_TEST_PACKAGE" == "docker" ]; then
    _uname="Docker"
  fi
  Glb_Arch=$(uname -m)
  echo_debug "Uname: $_uname"
  if [[ "$_uname" = *"MINGW64_NT"* ]]; then
    Glb_OS="windows"
  elif [[ "$_uname" = "Darwin" ]]; then
    Glb_OS="darwin"
  elif [[ "$_uname" = "Linux" ]]; then
    Glb_OS="linux"
  elif [[ "$_uname" = "Docker" ]]; then
    Glb_OS="docker"
  else
    echo_error_exit "Unknown OS: $_uname"
  fi

  if [[ "$Glb_Arch" == "aarch64" ]]; then
    Glb_Chromium=$(which chromium-browser)
    Glb_ChromeDriver=$(which chromedriver)
    if [[ -z $Glb_Chromium ]] || [[ -z $Glb_ChromeDriver ]]; then
      echo_error_exit "Chromium and Chromedriver must be installed! Chromium: $Glb_Chromium, ChromeDriver: $Glb_ChromeDriver"
    fi
  fi

  echo_info "Running on OS: $Glb_OS"
  echo_info "Running on Arch: $Glb_Arch"

  readonly Glb_OS Glb_Arch Glb_Chromium Glb_ChromeDriver
}

# ----------------------------------------------------------------------------
# Get version to compare
# ----------------------------------------------------------------------------
function getver() {
  printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ')
}

# ----------------------------------------------------------------------------
# Compare version
# ----------------------------------------------------------------------------
function vge() {
  if [ $(getver $1) -ge $(getver $2) ]; then
    echo 1
  else
   echo 0
  fi
}

# ----------------------------------------------------------------------------
# Method to get Kibana package
# ----------------------------------------------------------------------------
function get_kibana_pkg() {

  if [ ! -z $Glb_Pkg_Name ]; then
    return
  fi

  # Get if oss packages are available
  local _splitStr=(${Glb_Kibana_Version//./ })
  local _version=${_splitStr[0]}.${_splitStr[1]}
  local _isOssSupported=$(vge $_version "6.3")
  local _isUbiSupported=$(vge $_version "7.10")

  # Package type
  local _pkgType="${TEST_KIBANA_BUILD:-"basic"}"
  if ! [[ "$_pkgType" =~ ^(oss|basic|default|ubi8)$ ]]; then
    echo_error_exit "Unknown build type: $_pkgType"
  fi
  if [[ "$_pkgType" == "oss" && $_isOssSupported == 1 ]]; then
    _pkgType="-oss"
  elif [[ "$_pkgType" = "ubi8" && $_isUbiSupported == 1 && $Glb_KbnSkipUbi == "no" ]]; then
    _pkgType="-ubi8"
  else
    _pkgType=""
  fi

  local _pkgExt="${ESTF_TEST_PACKAGE:-"tar.gz"}"
  if [[ "$Glb_OS" = "linux" ]]; then
    if ! [[ "$_pkgExt" =~ ^(tar\.gz|deb|rpm)$ ]]; then
      echo_error_exit "Unknown package type: $_pkgExt"
    fi
  fi

  # OS and package name
  local _pkgName=""

  if [[ "$Glb_OS" = "windows" ]]; then
    if [[ $_isOssSupported == 1 ]]; then
      _pkgName="windows-x86_64.zip"
    else
      _pkgName="windows-x86.zip"
    fi
  elif [[ "$Glb_OS" = "darwin" ]]; then
    _pkgName="darwin-x86_64.tar.gz"
  elif [[ "$Glb_OS" = "linux" ]]; then
    _pkgName="linux-${Glb_Arch}.${_pkgExt}"
    if [ "$_pkgExt" = "deb" ] && [ "$Glb_Arch" = "x86_64" ]; then
      _pkgName="amd64.${_pkgExt}"
    elif [ "$_pkgExt" = "deb" ] && [ "$Glb_Arch" = "aarch64" ]; then
      _pkgName="arm64.${_pkgExt}"
    elif [ "$_pkgExt" = "rpm" ]; then
      _pkgName="${Glb_Arch}.${_pkgExt}"
    fi
  elif [[ "$Glb_OS" = "docker" ]]; then
    _pkgName="docker-image.tar.gz"
  else
    echo_error_exit "Unknown OS: $Glb_OS"
  fi

  # The name of ES package is different in 6.8
  _esPkgName="-${_pkgName}"
  if [[ "$Glb_Kibana_Version" == *"6.8"* ]]; then
    _esPkgName=".tar.gz"
    if [[ "$Glb_OS" = "windows" ]]; then
      _esPkgName=".zip"
    fi
  fi

  # Set remote
  if [[ "$Glb_OS" = "darwin" ]]; then
    export SELENIUM_REMOTE_URL="http://localhost:4444/wd/hub"
    if [[ "$Glb_Kibana_Version" == *"6.8"* ]]; then
      export SELENIUM_REMOTE_URL="http://localhost:4545/wd/hub"
    fi
  fi

  Glb_Pkg_Name="kibana${_pkgType}-${Glb_Kibana_Version}-${_pkgName}"
  Glb_Es_Pkg_Name="elasticsearch${_pkgType}-${Glb_Kibana_Version}${_esPkgName}"

  export DOCKER_ES_IMG_NAME="elasticsearch${_pkgType}"
  export DOCKER_ES_IMG_TAG="${Glb_Kibana_Version}"
  export DOCKER_KB_IMG_NAME="kibana${_pkgType}"
  export DOCKER_KB_IMG_TAG="${Glb_Kibana_Version}"

  readonly Glb_Pkg_Name Glb_Es_Pkg_Name
}

# ----------------------------------------------------------------------------
# Method to check if Kibana package URL exists
# ----------------------------------------------------------------------------
function get_kibana_url() {

  if [ ! -z $Glb_Kibana_Url ]; then
    return
  fi

  local _host="https://${Glb_Build_Server}.elastic.co"
  if [[ "$Glb_Build_Server" == "staging" ]]; then
    _host=$_host/${ESTF_BUILD_ID}
  fi
  local _path="downloads/kibana"
  local _es_path="downloads/elasticsearch"

  Glb_Kibana_Url="$_host/$_path/$Glb_Pkg_Name"

  local _urlExists=$(curl -s --head -f "${Glb_Kibana_Url}"; echo $?)
  if [[ $_urlExists -ne 0 ]]; then
    echo_error_exit "URL does not exist: $Glb_Kibana_Url"
  fi

  echo_info "Kibana URL: $Glb_Kibana_Url"

  # Set the elasticsearch snapshot for functional tests
  Glb_Es_Url="$_host/$_es_path/$Glb_Es_Pkg_Name"
  export KBN_ES_SNAPSHOT_URL="$Glb_Es_Url"
  echo_info "Elasticsearch URL: $Glb_Es_Url"

  readonly Glb_Kibana_Url Glb_Es_Url
}

# ----------------------------------------------------------------------------
# Method to download and extract Kibana package
# ----------------------------------------------------------------------------
function download_and_extract_package() {
  if [ ! -z $Glb_Kibana_Dir ]; then
    return
  fi

  echo_info "Kibana root build install dir: $Glb_Install_Dir"
  echo_info "KibanaUrl from $Glb_Kibana_Url"

  local _pkgName="$Glb_Install_Dir/${Glb_Kibana_Url##*/}"
  local _dirName=""
  if [[ -z $TEST_SKIP_KIBANA_INSTALL ]]; then
    curl --silent -o $_pkgName $Glb_Kibana_Url
  fi
  if [[ "$Glb_OS" == "windows" ]]; then
    _dirName=$(zipinfo -1 "$_pkgName" | head -n 1)
  else
    _dirName=$(tar tf "$_pkgName" | head -n 1)
  fi
  _dirName=${_dirName%%/*}

  Glb_Kibana_Dir="$Glb_Install_Dir/$_dirName"
  if [ -d "$Glb_Kibana_Dir" ]; then
      if [[ -z $TEST_SKIP_KIBANA_INSTALL ]]; then
        echo_info "Clearing previous Kibana install"
        rm -rf "$Glb_Kibana_Dir"
      fi
  fi

  if [[ -z $TEST_SKIP_KIBANA_INSTALL ]]; then
    if [[ "$Glb_OS" == "windows" ]]; then
      unzip -qo "$_pkgName" -d "$Glb_Install_Dir"
    else
      tar xfz "$_pkgName" -C "$Glb_Install_Dir"
    fi
  fi

  if [[ ! -z $TEST_SKIP_KIBANA_INSTALL ]]; then
    if [ ! -d "$Glb_Kibana_Dir" ]; then
      echo_error_exit "Kibana directory does not exist"
    fi
  fi

  echo_info  "Using Kibana install: $Glb_Kibana_Dir"

  readonly Glb_Kibana_Dir
}

# -----------------------------------------------------------------------------
# Method to set java home
# -----------------------------------------------------------------------------
function set_java_home() {
  echo_info "Set JAVA_HOME"

  if [ ! -z $JENKINS_HOME ]; then
    if [[ "$Glb_OS" == "windows" ]]; then
      export JAVA_HOME="c:\Users\jenkins\.java\java11"
    elif [[ "$Glb_Arch" == "aarch64" ]]; then
      export JAVA_HOME="/var/lib/jenkins/.java/adoptopenjdk11"
    elif [[ "$Glb_Arch" == "x86_64" ]]; then
      export JAVA_HOME="/var/lib/jenkins/.java/java11"
    fi
  else
    if [[ "$Glb_OS" == "windows" ]]; then
      export JAVA_HOME="c:\PROGRA~1\Java\jdk11"
    elif [[ "$Glb_OS" == "darwin" ]]; then
      export JAVA_HOME="/Library/Java/JavaVirtualMachines/jdk-11.0.1.jdk/Contents/Home"
    elif [ $ESTF_TEST_PACKAGE = "rpm" ]; then
      export JAVA_HOME="/usr/lib/jvm/java-11"
    elif [[ "$Glb_Arch" == "aarch64" ]]; then
      export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-arm64"
    elif [[ "$Glb_Arch" == "x86_64" ]]; then
      export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    fi
  fi

  if [[ ! -d $JAVA_HOME ]]; then
      echo_error_exit "JAVA_HOME does not exist: $JAVA_HOME"
  fi
}

# -----------------------------------------------------------------------------
# Method to check if in Kibana repo
# -----------------------------------------------------------------------------
function in_kibana_repo() {
  local _dir="$(pwd)"
  if [ ! -f "$_dir/package.json" ] || [ ! -f "$_dir/.node-version" ]; then
    echo_error_exit "CI setup must be run within a Kibana repo"
  fi

  check_test_files

  git checkout test
  git checkout x-pack/test
  git checkout .yarnrc
}

# -----------------------------------------------------------------------------
# Method to install node
# -----------------------------------------------------------------------------
function install_node() {
  local _dir="$(pwd)"
  local _nodeVersion="$(cat $_dir/.node-version)"
  local _nodeDir="$Glb_Cache_Dir/node/$_nodeVersion"
  local _nodeBin=""
  local _nodeUrl=""

  if [[ "$Glb_OS" == "windows" ]]; then
    # This variable must be set in the user path - done in jenkins
    _nodeBin="$HOME/node"
    _nodeUrl="https://nodejs.org/dist/v$_nodeVersion/node-v$_nodeVersion-win-x64.zip"
  elif [[ "$Glb_OS" == "darwin" ]]; then
    _nodeBin="$_nodeDir/bin"
    _nodeUrl="https://nodejs.org/dist/v$_nodeVersion/node-v$_nodeVersion-darwin-x64.tar.gz"
  elif [[ "$Glb_OS" == "linux" ||  "$Glb_OS" == "docker" ]]; then
    _nodeBin="$_nodeDir/bin"
    if [[ "$Glb_Arch" == "x86_64" ]]; then
      _nodeUrl="https://nodejs.org/dist/v$_nodeVersion/node-v$_nodeVersion-linux-x64.tar.gz"
    elif [[ "$Glb_Arch" == "aarch64" ]]; then
      _nodeUrl="https://nodejs.org/dist/v$_nodeVersion/node-v$_nodeVersion-linux-arm64.tar.gz"
    else
      echo_error_exit "Unknown arch: $Glb_Arch"
    fi
  else
    echo_error_exit "Unknown OS: $Glb_OS"
  fi

  echo_info "Node: version=v${_nodeVersion} dir=${_nodeDir}"

  echo_info "Setting up node.js"
  if [ -x "$_nodeBin/node" ] && [ "$($_nodeBin/node --version)" == "v$_nodeVersion" ]; then
    echo_info "Reusing node.js install"
  else
    if [ -d "$_nodeDir" ]; then
      echo_info "Clearing previous node.js install"
      rm -rf "$_nodeDir"
    fi

    echo_info "Downloading node.js from $_nodeUrl"
    mkdir -p "$_nodeDir"
    if [[ "$Glb_OS" == "windows" ]]; then
      local _nodePkg="$_nodeDir/${_nodeUrl##*/}"
      curl --silent -o $_nodePkg $_nodeUrl
      unzip -qo $_nodePkg -d $_nodeDir
      mv "${_nodePkg%.*}" "$_nodeBin"
    else
      curl --silent "$_nodeUrl" | tar -xz -C "$_nodeDir" --strip-components=1
    fi
  fi

  echo_debug "Node bin is here: "
  echo_debug $(ls $_nodeBin)
  export PATH="$_nodeBin:$PATH"
  hash -r

  echo_debug "Node is here: "
  if [[ "$Glb_OS" == "windows" ]]; then
    echo_debug $(where node)
  else
    echo_debug $(which node)
  fi
  echo_debug "$PATH"
}

# -----------------------------------------------------------------------------
# Method to install yarn
# -----------------------------------------------------------------------------
function install_yarn() {
  echo_info "Installing yarn"
  local _yarnVersion="$(node -e "console.log(String(require('./package.json').engines.yarn || '').replace(/^[^\d]+/,''))")"
  npm install -g yarn@^${_yarnVersion}

  #local _yarnDir="$Glb_Cache_Dir/yarn/$_yarnVersion"
  #export PATH="$_yarnDir/bin:$PATH"
  local _yarnGlobalDir="$(yarn global bin)"
  export PATH="$PATH:$_yarnGlobalDir"
  hash -r

  echo_debug "Yarn is here: "
  if [[ "$Glb_OS" == "windows" ]]; then
    echo_debug $(where node)
  else
    echo_debug $(which node)
  fi
}

# ----------------------------------------------------------------------------
# Method to bootstrap
# ----------------------------------------------------------------------------
function yarn_kbn_bootstrap() {
  echo_info "Installing node.js dependencies"
  #yarn config set cache-folder "$Glb_Cache_Dir/yarn"

  if $Glb_ChromeDriverHack; then
    echo_warning "Temporary update package.json bump chromedriver."
    sed -i 's/"chromedriver": "^83.0.0"/"chromedriver": "^84.0.0"/g' package.json
  fi

  # For windows testing
  Glb_YarnNetworkTimeout=$(grep "network-timeout" .yarnrc | wc -l)
  if [ $Glb_YarnNetworkTimeout -eq 0 ]; then
    echo "network-timeout 600000" >> .yarnrc
  fi

  if [[ "$Glb_Arch" == "aarch64" ]]; then
    local _filename=test/functional/services/remote/webdriver.ts
    sed -i 's/new chrome.ServiceBuilder(chromeDriver.path)/new chrome.ServiceBuilder(chromeDriverPath)/g' $_filename
    sed -i '/const headlessBrowser: string = process.env.TEST_BROWSER_HEADLESS as string;/a const chromeDriverPath = process.env.TEST_BROWSER_CHROMEDRIVER_PATH || chromeDriver.path;' $_filename
  fi

  if [[ "$Glb_Arch" != "aarch64" ]]; then
    # To deal with mismatched chrome versions on CI workers
    export CHROMEDRIVER_FORCE_DOWNLOAD=true
    export DETECT_CHROMEDRIVER_VERSION=true
  fi

  yarn kbn bootstrap --prefer-offline

  if [ $? -ne 0 ]; then
    echo_error_exit "yarn kbn bootstrap failed!"
  fi

  Glb_KbnBootStrapped="yes"
}

# ----------------------------------------------------------------------------
# Method to build docker image
# ----------------------------------------------------------------------------
function yarn_build_docker() {
  yarn build --no-oss --docker --skip-docker-ubi

  if [ $? -ne 0 ]; then
    echo_error_exit "yarn build docker failed!"
  fi
}

# ----------------------------------------------------------------------------
# Method to get kibana es snapshot docker image
# ----------------------------------------------------------------------------
function get_kbn_es_docker_snapshot() {
  if [ ! -z $ESTF_SKIP_KBN_ES_SNAPSHOT ]; then
    return
  fi
  echo_info "Get Kibana Elasticsearch Docker Snapshot"
  _url=$(curl -sX GET https://storage.googleapis.com/kibana-ci-es-snapshots-daily/${ESTF_KBN_ES_SNAPSHOT_VERSION}/manifest-latest-verified.json | jq '.archives[] | select(.platform=="docker") | .url')
  curl -s "${_url//\"}" | docker load -i /dev/stdin
  if [ $? -ne 0 ]; then
    echo_error_exit "Get and load docker image: $_url failed!"
  fi
}

# ----------------------------------------------------------------------------
# Method to run kbn clean
# ----------------------------------------------------------------------------
function yarn_kbn_clean() {
  echo_info "In yarn_kbn_clean"

  if [ $Glb_KbnBootStrapped == "yes" ]; then
    yarn kbn clean
  fi
}

# ----------------------------------------------------------------------------
# Method to check if any files changed during bootstraping
# ----------------------------------------------------------------------------
function check_git_changes() {
  local _git_changes
  local _exclude

  _exclude="yarn.lock"

  if $Glb_ChromeDriverHack; then
    echo_warning "Modified package.json for chromedriver"
    _exclude+="|package.json"
  fi

  if [[ "$Glb_Arch" == "aarch64" ]]; then
    echo_warning "Modified remote webdriver service for chromedriver"
    _exclude+="|test/functional/services/remote/webdriver.ts"
  fi

  if [ $Glb_YarnNetworkTimeout -eq 0 ]; then
    echo_warning "Modified network timeout in .yarnrc"
    _exclude+="|.yarnrc"
  fi

  _git_changes="$(git ls-files --modified | grep -Ev $_exclude)"

  if [ "$_git_changes" ]; then
    echo_error_exit "'yarn kbn bootstrap' caused changes to the following files:\n$_git_changes"
  fi
}

# -----------------------------------------------------------------------------
# Method to setup CI environment
# -----------------------------------------------------------------------------
function run_ci_setup() {
  if [[ ! -z $TEST_SKIP_CI_SETUP ]]; then
    return
  fi
  get_os
  in_kibana_repo
  install_node
  install_yarn
  yarn_kbn_bootstrap
  check_git_changes
}

# -----------------------------------------------------------------------------
# Method to setup CI environment
# -----------------------------------------------------------------------------
function run_ci_setup_get_docker_images() {
  run_ci_setup
  yarn_build_docker
  get_kbn_es_docker_snapshot
}

# -----------------------------------------------------------------------------
# Method to cleanup CI environment
# -----------------------------------------------------------------------------
function run_ci_cleanup() {
  if [ $Glb_KbnClean == "yes" ]; then
    remove_node_modules_dir
    remove_install_dir
    remove_es_install_dir
  fi
}

# -----------------------------------------------------------------------------
# Method to install Kibana
# -----------------------------------------------------------------------------
function install_kibana() {
  create_install_dir
  get_build_server
  get_version
  get_os
  get_kibana_pkg
  get_kibana_url
  download_and_extract_package
  set_java_home
}

# *****************************************************************************
# SECTION: Percy visual testing functions
# *****************************************************************************

# -----------------------------------------------------------------------------
# Method to set percy target branch
# -----------------------------------------------------------------------------
function set_percy_target_branch() {
  get_branch
  export PERCY_TARGET_BRANCH=$Glb_Kibana_Branch
  export PERCY_BRANCH=${branch_specifier##*refs\/heads\/}
  echo_info "PERCY_BRANCH: $PERCY_BRANCH"
  echo_info "PERCY_TARGET_BRANCH: $PERCY_TARGET_BRANCH"
}

# -----------------------------------------------------------------------------
# Method to set puppeteer executable
# -----------------------------------------------------------------------------
function set_puppeteer_exe() {
  export PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome
}

# -----------------------------------------------------------------------------
# Method to copy basic visual tests into Kibana repo
# -----------------------------------------------------------------------------
function cp_visual_tests() {
  # Get files
  git submodule -b $(basename $branch_specifier) add https://github.com/elastic/kibana-visual-tests
  if [ $? -ne 0 ]; then
    echo_error_exit "Submodule checkout failed!"
  fi
  cp -rf kibana-visual-tests/test/visual_regression test
  git rm -f kibana-visual-tests
  git rm -f .gitmodules
  rm -rf .git/modules/kibana-visual-tests/
}

# -----------------------------------------------------------------------------
# Method to copy xpack visual tests into Kibana repo
# -----------------------------------------------------------------------------
function cp_xpack_visual_tests() {
  # Get files
  git submodule -b $(basename $branch_specifier) add https://github.com/elastic/kibana-visual-tests
  if [ $? -ne 0 ]; then
    echo_error_exit "Submodule checkout failed!"
  fi
  cp -rf kibana-visual-tests/x-pack/test/visual_regression x-pack/test
  git rm -f kibana-visual-tests
  git rm -f .gitmodules
  rm -rf .git/modules/kibana-visual-tests/
}

# ----------------------------------------------------------------------------
# Get Percy version from package.json file
# ----------------------------------------------------------------------------
function check_percy_pkg() {
  local _percyVersion=$(cat package.json | \
                        grep "percy" | \
                        cut -d ':' -f 2 | \
                        tr -d "^,\"\ +" | \
                        xargs)

  if [[ -z "$_percyVersion" ]]; then
    echo "No percy package available"
    exit 1
  fi
}

# *****************************************************************************
# SECTION: Running test functions
# *****************************************************************************

# -----------------------------------------------------------------------------
# Method to set kibana version from build specifier for flaky test runner
# -----------------------------------------------------------------------------
function check_kibana_version() {
   if [ -z $ESTF_KIBANA_VERSION ]; then
    echo_error_exit "ESTF_KIBANA_VERSION can't be empty!"
  fi
}

# -----------------------------------------------------------------------------
# Method to set cloud and kibana es snapshot version for pr testing
# -----------------------------------------------------------------------------
function set_cloud_es_version() {
  _ver=$(curl -sX GET "https://raw.githubusercontent.com/elastic/kibana/${ESTF_KIBANA_VERSION}/package.json" | jq '.version')
  echo $_ver
  if [ ! -z $ESTF_USE_BC ]; then
    export ESTF_CLOUD_VERSION="${_ver//\"}"
  else
    export ESTF_CLOUD_VERSION="${_ver//\"}-SNAPSHOT"
  fi
  export ESTF_KBN_ES_SNAPSHOT_VERSION="${_ver//\"}"
  _sha=$(curl -sX GET https://storage.googleapis.com/kibana-ci-es-snapshots-daily/${ESTF_KBN_ES_SNAPSHOT_VERSION}/manifest-latest-verified.json | jq '.sha')
  export ESTF_ELASTICSEARCH_COMMIT="${_sha}"
}

# -----------------------------------------------------------------------------
# Method to check cloud version for flaky test runner
# -----------------------------------------------------------------------------
function check_cloud_version() {
  if [ -z $ESTF_CLOUD_VERSION ]; then
    echo_error_exit "ESTF_CLOUD_VERSION can't be empty!"
  fi
}

# -----------------------------------------------------------------------------
# Method to check test suite values are all in one group
# -----------------------------------------------------------------------------
function _check_array_vals_eq() {
    arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
      echo_error_exit "ESTF_FLAKY_TEST_SUITE is empty or is not in proper format"
    elif awk 'v && $1!=v{ exit 1 }{ v=$1 }' <(printf "%s\n" "${arr[@]}"); then
      echo_info "Test Suite Group: ${arr[0]}"
    else
      echo_error_exit "ESTF_FLAKY_TEST_SUITE can not have mixed values: basic, xpack, xpackExt"
    fi
}

# -----------------------------------------------------------------------------
# Method to check test suite for flaky test runner
# -----------------------------------------------------------------------------
function check_test_suite() {
  IFS='
  '
  types=()
  for item in $ESTF_FLAKY_TEST_SUITE
  do
    testSuiteRoot=${item%%/*}
    if [[ "$testSuiteRoot" == "test" ]] ||
       [[ "$testSuiteRoot" == *"basicGrp"* ]]; then
      types+=( "basic" )
    elif [[ "$testSuiteRoot" == "x-pack" ]]; then
      if [[ "$item" != *"/functional/"* ]]; then
        types+=( "xpackExt" )
      else
        types+=( "xpack" )
      fi
    elif [[ "$testSuiteRoot" == *"xpackGrp"* ]]; then
      types+=( "xpack" )
    elif  [[ "$testSuiteRoot" == *"xpackExt"* ]]; then
      types+=( "xpackExt" )
    fi
  done

  _check_array_vals_eq "${types[@]}"
}

# -----------------------------------------------------------------------------
# Method to set test suite for flaky test runner
# -----------------------------------------------------------------------------
function set_test_group() {
  export ESTF_TEST_GROUP="${ESTF_FLAKY_TEST_SUITE%%/*}"
}

# -----------------------------------------------------------------------------
# Method to check number of executions for flaky test runner
# -----------------------------------------------------------------------------
function check_number_executions() {
  ESTF_NUMBER_EXECUTIONS=$( expr $ESTF_NUMBER_EXECUTIONS + 0 )
  re='^[0-9]+$'
  if ! [[ $ESTF_NUMBER_EXECUTIONS =~ $re ]] ; then
    echo_error_exit "ESTF_NUMBER_EXECUTIONS is not a number!"
  fi
}

# -----------------------------------------------------------------------------
# Method to set number of executions for flaky test runner
# -----------------------------------------------------------------------------
function set_number_executions_deployments() {
  # Apply min and max
  if [ $ESTF_NUMBER_EXECUTIONS -lt 0 ]; then
    ESTF_NUMBER_EXECUTIONS=1
  fi

  if [ $ESTF_NUMBER_EXECUTIONS -gt 40 ]; then
    ESTF_NUMBER_EXECUTIONS=40
  fi

  ESTF_NUMBER_DEPLOYMENTS=1
  if [ $ESTF_NUMBER_EXECUTIONS -gt 20 ]; then
    ESTF_NUMBER_DEPLOYMENTS=2
  fi

  ESTF_NUMBER_EXECUTIONS=$(($ESTF_NUMBER_EXECUTIONS / $ESTF_NUMBER_DEPLOYMENTS))

  export ESTF_NUMBER_EXECUTIONS
  export ESTF_NUMBER_DEPLOYMENTS

  echo_debug "ESTF_NUMBER_EXECUTIONS: $ESTF_NUMBER_EXECUTIONS"
  echo_debug "ESTF_NUMBER_DEPLOYMENTS: $ESTF_NUMBER_DEPLOYMENTS"
}

# -----------------------------------------------------------------------------
# Method to check test type for flaky test runner
# -----------------------------------------------------------------------------
function check_test_type() {
  # Get the type of test to run
  if [ -z $ESTF_TEST_PLATFORM ]; then
    echo_error_exit "ESTF_TEST_PLATFORM can't be empty!"
  fi

  valid_platforms=()
  valid_platforms+=('saas')
  # TODO: add eck and ece later
  if [[ " ${valid_platforms[*]} " != *"$ESTF_TEST_PLATFORM"* ]]; then
    echo_error_exit "Invalid ESTF_TEST_PLATFORM, must be one of $valid_platforms"
  fi
}

# -----------------------------------------------------------------------------
# Method create job file for flaky test runner
# -----------------------------------------------------------------------------
function create_matrix_job_file() {
  local matrixJobDir="${JENKINS_HOME:-ci/kibana/jobs}"
  local matrixJobFile="$matrixJobDir/flaky_jobs.yml"

  if [ ! -d $matrixJobDir ]; then
    echo_error_exit "Matrix job directory does not exist!"
  fi

  echo "TASK:" > $matrixJobFile
  echo "  - ${ESTF_TEST_PLATFORM}_run_kibana_tests" >> $matrixJobFile
  echo "JOB: " >> $matrixJobFile
  for i in $(seq 1 1 $ESTF_NUMBER_DEPLOYMENTS); do
    echo "  - flakyRun$i" >> $matrixJobFile
  done
  echo "exclude: ~" >> $matrixJobFile
}

# -----------------------------------------------------------------------------
# Method to get test file
# -----------------------------------------------------------------------------
function get_test_file() {
  local item=$1

  testFile=""
  if [ -d "$item" ]; then
    if [ -f "$item/index.js" ]; then
      testFile="$item/index.js"
    elif [ -f "$item/index.ts" ]; then
      testFile="$item/index.ts"
    fi
  elif [ -f "$item" ]; then
    testFile=$item
  fi
  echo $testFile
}

# -----------------------------------------------------------------------------
# Method to check test files and directories exist
# This can be files or top level feature directories.
# TODO: Add test/<extended tests>
# Examples:
#   test/functional/<feature>
#   test/functional/<feature>/<file>
#   x-pack/test/functional/<feature>
#   x-pack/test/functional/<feature>/<file>
#   x-pack/test/<extended test>/<feature>
#   x-pack/test/<extended test>/<feature>/<file>
#   test/functional
#   x-pack/functional
# -----------------------------------------------------------------------------
function check_test_files() {
  IFS='
  '
  errors=0
  for item in $ESTF_FLAKY_TEST_SUITE
  do
    testFile=$(get_test_file $item)
    if [ -z $testFile ]; then
      echo_error "File does not exist: $item!"
      errors=1
    fi
  done
  if [ $errors -eq 1 ]; then
    echo_error_exit "ESTF_FLAKY_TEST_SUITE not all paths are valid!"
  fi
}

# -----------------------------------------------------------------------------
# Method to run flaky test runner cloud prechecks
# -----------------------------------------------------------------------------
function flaky_test_runner_cloud_prechecks() {
  check_kibana_version
  check_cloud_version
  check_test_suite
  check_number_executions
  set_number_executions_deployments
  check_test_type
  create_matrix_job_file
}

# -----------------------------------------------------------------------------
# Method to run pr test runner cloud prechecks
# -----------------------------------------------------------------------------
function pr_cloud_prechecks() {
  check_kibana_version
  set_cloud_es_version
}

# -----------------------------------------------------------------------------
# Method to run flaky Kibana tests
# TODO: Add eck, ece and on-prem
# (Mainly for functional UI tests)
# -----------------------------------------------------------------------------
function flaky_test_runner() {
  echo_info "In flaky_test_runner"

  cloud_platforms=()
  cloud_platforms+=('saas')
  cloud_platforms+=('ece')
  cloud_platforms+=('eck')

  set_test_group
  set_number_executions_deployments

  # If just the top level directory is specified to run whole
  # suite, then set extended group
  if [[ $ESTF_TEST_GROUP == "x-pack" ]] &&
     [[ "$ESTF_FLAKY_TEST_SUITE" != *"/functional"* ]]; then
    ESTF_TEST_GROUP=xpackext
  fi

  if [[ " ${cloud_platforms[*]} " == *"$ESTF_TEST_PLATFORM"* ]]; then
    PLATFORM=cloud
  fi

  echo_debug "ESTF_TEST_GROUP: $ESTF_TEST_GROUP"
  echo_debug "ESTF_TEST_PLATFORM: $ESTF_TEST_PLATFORM"
  echo_debug "ESTF_FLAKY_TEST_SUITE: $ESTF_FLAKY_TEST_SUITE"

  case "$ESTF_TEST_GROUP" in
    basic|test)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_basic_tests
      else
        run_basic_tests
      fi
      ;;
    xpack|x-pack)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_xpack_func_tests
      else
        run_xpack_func_tests
      fi
      ;;
    xpackext)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_xpack_ext_tests
      else
        run_xpack_ext_tests
      fi
      ;;
    basicGrp*)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_basic_tests $ESTF_TEST_GROUP
      else
        run_basic_tests $ESTF_TEST_GROUP
      fi
      ;;
    xpackGrp*)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_xpack_func_tests $ESTF_TEST_GROUP
      else
        run_xpack_func_tests $ESTF_TEST_GROUP
      fi
      ;;
    xpackExt*)
      if [ $PLATFORM == "cloud" ]; then
        run_cloud_xpack_ext_tests
      else
        run_xpack_ext_tests false $ESTF_TEST_GROUP
      fi
      ;;
    *)
      echo_error_exit "ESTF_TEST_GROUP '$ESTF_TEST_GROUP' is invalid group"
      ;;
  esac

  echo "DONE!"
}

# -----------------------------------------------------------------------------
# Method to run Kibana unit tests
# -----------------------------------------------------------------------------
function run_unit_tests() {
  echo_info "In run_unit_tests"

  run_ci_setup

  export TEST_ES_FROM=snapshot
  export TEST_BROWSER_HEADLESS=1

  echo_info " -> Running unit tests"
  "$(FORCE_COLOR=0 yarn bin)/grunt" jenkins:unit --from=${TEST_ES_FROM};
  RC=$?

  run_ci_cleanup

  exit_script $RC "Unit tests failed"
}

# -----------------------------------------------------------------------------
# Method to run Kibana xpack unit tests
# -----------------------------------------------------------------------------
function run_xpack_unit_tests() {
  echo_info "In run_xpack_unit_tests"

  run_ci_setup

  export TEST_ES_FROM=snapshot
  export TEST_BROWSER_HEADLESS=1

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  echo " -> Running mocha tests"
  yarn test
  echo ""
  echo ""
  RC1=$?

  echo " -> Running jest tests"
  node scripts/jest --ci --verbose
  echo ""
  echo ""
  RC2=$?

  echo " -> Running SIEM cyclic dependency test"
  cd "$XPACK_DIR"
  node legacy/plugins/siem/scripts/check_circular_deps
  echo ""
  echo ""
  RC3=$?

  echo " -> Running jest contracts tests"
  cd "$XPACK_DIR"
  node scripts/jest_contract.js --ci --verbose
  echo ""
  echo ""
  RC4=$?

  # echo " -> Running jest integration tests"
  # node scripts/jest_integration --ci --verbose
  # echo ""
  # echo ""

  run_ci_cleanup

  rclist=($RC1 $RC2 $RC3 $RC4)

  check_status_ok ${rclist[*]} && exit_script || exit_script 1 "X-pack unit test failed!"
}

# -----------------------------------------------------------------------------
# Method to run basic tests from Kibana repo, ones in test/ directory
# -----------------------------------------------------------------------------
function run_basic_tests() {
  echo_info "In run_basic_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  run_ci_setup

  includeTags=$(update_config "test/functional/config.js" $testGrp)
  update_test_files
  remove_oss

  TEST_KIBANA_BUILD=basic
  install_kibana

  export TEST_BROWSER_HEADLESS=1
  if [[ "$Glb_Arch" == "aarch64" ]]; then
    export TEST_BROWSER_BINARY_PATH=$Glb_Chromium
    export TEST_BROWSER_CHROMEDRIVER_PATH=$Glb_ChromeDriver
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running basic functional tests, run $i of $maxRuns"
    eval node scripts/functional_tests \
          --esFrom snapshot \
          --kibana-install-dir=${Glb_Kibana_Dir} \
          --config test/functional/config.js \
          --debug " $includeTags" \
          -- --server.maxPayloadBytes=1679958
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "basic Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run x-pack tests from Kibana repo, ones in x-pack/test/ directory
# -----------------------------------------------------------------------------
function run_xpack_func_tests() {
  echo_info "In run_xpack_func_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  run_ci_setup

  includeTags=$(update_config "x-pack/test/functional/config.js" $testGrp)
  update_test_files

  TEST_KIBANA_BUILD=default
  install_kibana

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  export TEST_BROWSER_HEADLESS=1
  if [[ "$Glb_Arch" == "aarch64" ]]; then
    export TEST_BROWSER_BINARY_PATH=$Glb_Chromium
    export TEST_BROWSER_CHROMEDRIVER_PATH=$Glb_ChromeDriver
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running xpack func tests, run $i of $maxRuns"
    eval node scripts/functional_tests \
          --esFrom=snapshot \
          --config test/functional/config.js \
          --kibana-install-dir=${Glb_Kibana_Dir} \
          --debug " $includeTags"
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "X-Pack Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run x-pack tests from Kibana repo, ones in x-pack/test/ directory
# -----------------------------------------------------------------------------
function run_xpack_ext_tests() {
  echo_info "In run_xpack_ext_tests"
  local funcTests="${1:- false}"
  local testGrp=$2
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  run_ci_setup
  update_test_files

  TEST_KIBANA_BUILD=default
  install_kibana

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  export TEST_BROWSER_HEADLESS=1
  if [[ "$Glb_Arch" == "aarch64" ]]; then
    export TEST_BROWSER_BINARY_PATH=$Glb_Chromium
    export TEST_BROWSER_CHROMEDRIVER_PATH=$Glb_ChromeDriver
  fi

  awk_exec="awk"
  if [[ "$Glb_OS" = "darwin" ]]; then
    awk_exec="gawk"
  fi

  # Note: It is done this way until kibana issue #42454 is resolved
  matches=$($awk_exec 'match($0, /test[\a-z.]+'\''/) { print substr($0,RSTART,RLENGTH-1) }' scripts/functional_tests.js)

  filter_matches=""
  for grp in ${!testGrp}; do
    cfgs=$(echo $matches | tr " " "\n" | grep "test/$grp[\a-z]*")
    filter_matches="${filter_matches} $cfgs"
  done

  cfgs=$matches
  if [ ! -z "$filter_matches" ]; then
    cfgs=$filter_matches
  fi

  cfgs=$(echo $cfgs | xargs -n1 | sort -u | xargs)

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    for cfg in $cfgs; do
      if [ $cfg == "test/functional/config.js" ] && [ $funcTests == "false" ]; then
        continue
      fi
      export ESTF_RUN_NUMBER=$i
      update_report_name $cfg

      echo " -> Running xpack ext tests config: $cfg, run $i of $maxRuns"
      node scripts/functional_tests \
        --esFrom=snapshot \
        --config $cfg \
        --kibana-install-dir=${Glb_Kibana_Dir} \
        --debug
      if [ $? -ne 0 ]; then
        failures=1
      fi
    done
  done

  run_ci_cleanup

  exit_script $failures "X-Pack Ext Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run basic tests from Kibana repo, ones in test/ directory for cloud platform
# -----------------------------------------------------------------------------
function run_cloud_basic_tests() {
  echo_info "In run_cloud_basic_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"
  local runWithSuperUser="${ESTF_RUN_SUPERUSER:-no}"

  run_ci_setup
  includeTags=$(update_config "test/functional/config.js" $testGrp)
  update_test_files

  export TEST_BROWSER_HEADLESS=1
  # To fix FTR ssl certificate issue: https://github.com/elastic/kibana/pull/73317
  export TEST_CLOUD=1

  if [[ "$runWithSuperUser" == "yes" ]] && [[ ! -z $TEST_KIBANA_PASS ]]; then
    sed -i "s/PageObjects.login.login('test_user', 'changeme');/PageObjects.login.login('elastic', '$TEST_KIBANA_PASS');/g" test/functional/page_objects/common_page.ts
  fi

  nodeOpts=" "
  if [ ! -z $NODE_TLS_REJECT_UNAUTHORIZED ] && [[ $NODE_TLS_REJECT_UNAUTHORIZED -eq 0 ]]; then
    nodeOpts="--no-warnings "
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running cloud basic functional tests, run $i of $maxRuns"
    eval node $nodeOpts scripts/functional_test_runner \
          --config test/functional/config.js \
          --exclude-tag skipCloud \
          --debug " $includeTags"
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "Cloud basic Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run cloud xpack tests
# -----------------------------------------------------------------------------
function run_cloud_xpack_func_tests() {
  echo_info "In run_cloud_xpack_func_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  run_ci_setup
  includeTags=$(update_config "x-pack/test/functional/config.js" $testGrp)
  update_test_files

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  export TEST_BROWSER_HEADLESS=1
  # To fix FTR ssl certificate issue: https://github.com/elastic/kibana/pull/73317
  export TEST_CLOUD=1

  nodeOpts=" "
  if [ ! -z $NODE_TLS_REJECT_UNAUTHORIZED ] && [[ $NODE_TLS_REJECT_UNAUTHORIZED -eq 0 ]]; then
    nodeOpts="--no-warnings "
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running cloud xpack func tests, run $i of $maxRuns"
    eval node $nodeOpts ../scripts/functional_test_runner \
          --config test/functional/config.js \
          --exclude-tag skipCloud \
          --debug " $includeTags"
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "Cloud X-Pack Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run cloud xpack tests
# -----------------------------------------------------------------------------
function run_cloud_xpack_ext_tests() {
  local testGrp="${1:-xpackExtAll}"
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  echo_info "In run_cloud_xpack_ext_tests"
  echo_warning "Not all tests are running yet on cloud"
  local funcTests="${1:- false}"

  run_ci_setup
  update_test_files

  export TEST_BROWSER_HEADLESS=1

  # To fix FTR ssl certificate issue: https://github.com/elastic/kibana/pull/73317
  export TEST_CLOUD=1

  # Note: Only the following tests run on cloud at this time
  varcfg="Glb_${testGrp}Cfg"
  cfgs=${!varcfg}

  if [[ ! -z $ESTF_FLAKY_TEST_SUITE ]]; then
    if [[ ! -z $ESTF_TEST_CONFIG ]]; then
      _cfgs=""
      errors=0
      for testconfig in $ESTF_TEST_CONFIG; do
        if [ ! -f $testconfig ]; then
          ((errors++))
          break
        fi
        _cfgs+="${testconfig#"x-pack/"}
        "
      done
    else
      _cfgs=""
      errors=0
      for flakytest in $ESTF_FLAKY_TEST_SUITE; do
        found=0
        for cfg in $cfgs; do
          if [ ! -f x-pack/$cfg ]; then
            continue
          fi
          IFS='/' read -a fields <<< $cfg
          cfgdir="x-pack/${fields[0]}/${fields[1]}/"
          if [[ "$flakytest" == *"$cfgdir"* ]]; then
            _cfgs+="$cfg
            "
            found=1
            break
          fi
        done
        if [ $found -eq 0 ]; then
          ((errors++))
          break
        fi
      done
    fi
    if [[ -z $_cfgs ]]; then
      echo_error_exit "!!!
      No configurations match your test suite.
      If your configuration needs to be added, open an issue in
      https://github.com/elastic/elastic-stack-testing/issues/new
      Only the following configs are currently accepted:
      $cfgs"
    elif [[ $errors -gt 0 ]]; then
      echo_error_exit "!!!
      Some configurations do not match your test suite.
      If your configuration needs to be added, open an issue in
      https://github.com/elastic/elastic-stack-testing/issues/new
      Only the following configs are currently accepted:
      $cfgs"
    fi
    cfgs=$(echo $_cfgs | xargs -n1 | sort -u | xargs)
  fi

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  nodeOpts=" "
  if [ ! -z $NODE_TLS_REJECT_UNAUTHORIZED ] && [[ $NODE_TLS_REJECT_UNAUTHORIZED -eq 0 ]]; then
    nodeOpts="--no-warnings "
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    for cfg in $cfgs; do
      if [ $cfg == "test/functional/config.js" ] && [ $funcTests == "false" ]; then
        continue
      fi
      if [ ! -f $cfg ]; then
        echo "Warning invalid configuration: $cfg"
        continue
      fi
      export ESTF_RUN_NUMBER=$i
      update_report_name $cfg

      echo " -> Running cloud xpack ext tests config: $cfg, run $i of $maxRuns"
      node $nodeOpts ../scripts/functional_test_runner \
        --config $cfg \
        --exclude-tag skipCloud \
        --debug
      if [ $? -ne 0 ]; then
        failures=1
      fi
    done
  done

  run_ci_cleanup

  exit_script $failures "Cloud X-Pack Ext Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run visual tests under Kibana repo tests/
# -----------------------------------------------------------------------------
function run_visual_tests_basic() {
  check_percy_pkg
  run_ci_setup
  set_percy_target_branch
  set_puppeteer_exe

  remove_oss
  TEST_KIBANA_BUILD=basic
  install_kibana

  export TEST_BROWSER_HEADLESS=1
  export LOG_LEVEL=debug

  echo_info "Running basic visual tests"
  yarn run percy exec -- -t 700 -- \
  node scripts/functional_tests \
    --kibana-install-dir=${Glb_Kibana_Dir} \
    --esFrom snapshot \
    --config test/visual_regression/config.ts \
    --debug
}

# -----------------------------------------------------------------------------
# Method to run visual tests under Kibana repo x-pack/tests/
# -----------------------------------------------------------------------------
function run_visual_tests_default() {
  check_percy_pkg
  run_ci_setup
  set_percy_target_branch
  set_puppeteer_exe

  TEST_KIBANA_BUILD=default
  install_kibana

  export TEST_BROWSER_HEADLESS=1
  export LOG_LEVEL=debug

  echo_info "Running default visual tests"
  yarn run percy exec -- -t 700 -- \
  node scripts/functional_tests \
    --kibana-install-dir=${Glb_Kibana_Dir} \
    --esFrom=snapshot \
    --config x-pack/test/visual_regression/config.ts \
    --debug
}

# -----------------------------------------------------------------------------
# Run with timeout
# -----------------------------------------------------------------------------
function run_with_timeout {
  cmd="$1"; timeout="$2";
  grep -qP '^\d+$' <<< $timeout || timeout=10
  (
    eval "$cmd" &
    child=$!
    trap -- "" SIGTERM
    (
      sleep $timeout
      kill $child 2> /dev/null
    ) &
    wait $child
  )
}

# -----------------------------------------------------------------------------
# Method wait for elasticsearch server to be ready
# -----------------------------------------------------------------------------
function _wait_for_es_ready_docker() {
  while true; do
    docker logs es01 | grep -E -i -w '(es01.*to \[GREEN\])|(to \[GREEN\].*elasticsearch)|(es01.*started)'

    if [ $? -eq 0 ]; then
      break
    fi
    sleep 5;
  done
}

# -----------------------------------------------------------------------------
# Method wait for elasticsearch server to be ready
# -----------------------------------------------------------------------------
function wait_for_es_ready_docker {
  local timeout=${1:-40}
  run_with_timeout _wait_for_es_ready_docker $timeout
  if [ $? -ne 0 ]; then
    echo_error_exit "Elasticsearch server not ready"
  fi
}

# -----------------------------------------------------------------------------
# Method wait for kibana server to be ready
# -----------------------------------------------------------------------------
function _wait_for_kbn_ready_docker {
  while true; do
    docker logs kib01 | grep -E -i -w 'Kibana.*http server running at'
    if [ $? -eq 0 ]; then
      break
    fi
    sleep 5;
  done
}

# -----------------------------------------------------------------------------
# Method wait for kibana server to be ready
# -----------------------------------------------------------------------------
function wait_for_kbn_ready_docker {
  local timeout=${1:-90}
  run_with_timeout _wait_for_kbn_ready_docker $timeout
  if [ $? -ne 0 ]; then
    echo_error_exit "Kibana server not ready"
  fi
}

# -----------------------------------------------------------------------------
# Method docker load
# -----------------------------------------------------------------------------
function docker_load {
  local type=${TEST_KIBANA_BUILD:-basic}

  get_build_server
  get_version
  get_os
  get_branch
  get_kibana_pkg
  get_kibana_url

  echo_info $Glb_Kibana_Url
  echo_info $Glb_Es_Url

  echo_info "Run docker elasticsearch load..."
  curl -s "${Glb_Es_Url}" | docker load -i /dev/stdin
  if [ $? -ne 0 ]; then
    echo_error_exit "Failed to load elasticsearch docker"
  fi

  echo_info "Run docker kibana load..."
  curl -s "${Glb_Kibana_Url}" | docker load -i /dev/stdin
  if [ $? -ne 0 ]; then
    echo_error_exit "Failed to load kibana docker"
  fi

  if [ "$type" == "basic" ]; then
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/settings/basic/kibana.yml --output kibana.yml
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/docker/basic/docker-compose.yml --output docker-compose.yml

    echo_info "Run docker compose up..."
    docker-compose up -d
    if [ $? -ne 0 ]; then
        echo_error_exit "Docker compose up failed"
    fi
    wait_for_es_ready_docker
    wait_for_kbn_ready_docker

    export TEST_KIBANA_PROTOCOL=http
    export TEST_KIBANA_PORT=5601
    export TEST_ES_PROTOCOL=http
    export TEST_ES_PORT=9200

  else

    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/settings/kibana.yml --output kibana.yml
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/docker/default/create-certs.yml --output create-certs.yml
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/docker/default/elastic-docker-tls.yml --output elastic-docker-tls.yml
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/docker/default/instances.yml --output instances.yml

    export COMPOSE_PROJECT_NAME=es
    export CERTS_DIR=/usr/share/elasticsearch/config/certificates

    echo_info "Run docker compose run for cert setup..."
    docker-compose -f create-certs.yml run --rm create_certs
    if [ $? -ne 0 ]; then
      echo_error_exit "Docker compose create certs failed"
    fi

    echo_info "Run docker compose up for passwords setup..."
    docker-compose -f elastic-docker-tls.yml up -d
    if [ $? -ne 0 ]; then
      echo_error_exit "Docker compose failed"
    fi

    echo_info "Run setup passwords..."
    docker exec es01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch \
                                   --url https://localhost:9200 > passwords.txt"
    if [ $? -ne 0 ]; then
      echo_error_exit "Elasticsearch setup passwords failed"
    fi

    espw=$(docker exec es01 /bin/bash -c "grep \"PASSWORD elastic\" passwords.txt" | awk '{print $4}')
    kbnpw=$(docker exec es01 /bin/bash -c "grep \"PASSWORD kibana_system\" passwords.txt" | awk '{print $4}')

    echo_info "Run docker compose stop..."
    docker-compose -f elastic-docker-tls.yml stop
    if [ $? -ne 0 ]; then
      echo_error_exit "Docker compose stop failed"
    fi

    echo_info "Run docker compose up..."
    sed -i "s/CHANGEME/$kbnpw/g" elastic-docker-tls.yml
    docker-compose -f elastic-docker-tls.yml up -d
    if [ $? -ne 0 ]; then
      echo_error_exit "Docker compose up failed"
    fi
    wait_for_es_ready_docker
    wait_for_kbn_ready_docker

    export TEST_KIBANA_PROTOCOL=https
    export TEST_KIBANA_PORT=5601
    export TEST_KIBANA_USER=elastic
    export TEST_KIBANA_PASS=$espw
    export TEST_ES_PROTOCOL=https
    export TEST_ES_PORT=9200
    export TEST_ES_USER=elastic
    export TEST_ES_PASS=$espw
    export NODE_TLS_REJECT_UNAUTHORIZED=0
    export TEST_IGNORE_CERT_ERRORS=1

  fi

}

# -----------------------------------------------------------------------------
# Method to run basic tests from Kibana repo, ones in test/ directory for docker
# -----------------------------------------------------------------------------
function run_standalone_basic_tests() {
  echo_info "In run_standalone_basic_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  TEST_KIBANA_BUILD=basic

  run_ci_setup
  includeTags=$(update_config "test/functional/config.js" $testGrp)
  update_test_files
  disable_security_user

  export TEST_BROWSER_HEADLESS=1

  install_standalone_servers

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running standalone basic functional tests, run $i of $maxRuns"
    eval node scripts/functional_test_runner \
          --config test/functional/config.js \
          --debug " $includeTags"
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "Standalone basic Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run docker xpack tests
# -----------------------------------------------------------------------------
function run_standalone_xpack_func_tests() {
  echo_info "In run_standalone_xpack_func_tests"
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  TEST_KIBANA_BUILD=default

  run_ci_setup

  includeTags=$(update_config "x-pack/test/functional/config.js" $testGrp)
  update_test_files

  export TEST_BROWSER_HEADLESS=1

  install_standalone_servers

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  nodeOpts=" "
  if [ ! -z $NODE_TLS_REJECT_UNAUTHORIZED ] && [[ $NODE_TLS_REJECT_UNAUTHORIZED -eq 0 ]]; then
    nodeOpts="--no-warnings "
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    export ESTF_RUN_NUMBER=$i
    update_report_name "test/functional/config.js"

    echo_info " -> Running standalone xpack func tests, run $i of $maxRuns"
    eval node $nodeOpts ../scripts/functional_test_runner \
          --config test/functional/config.js \
          --debug " $includeTags"
    if [ $? -ne 0 ]; then
      failures=1
    fi
  done

  run_ci_cleanup

  exit_script $failures "Standalone X-Pack Test failed!"
}

# -----------------------------------------------------------------------------
# Method to run docker xpack tests
# -----------------------------------------------------------------------------
function run_standalone_xpack_ext_tests() {
  local testGrp=$1
  local maxRuns="${ESTF_NUMBER_EXECUTIONS:-1}"

  echo_info "In run_standalone_xpack_ext_tests"
  local funcTests="${1:- false}"

  TEST_KIBANA_BUILD=default

  run_ci_setup

  update_test_files

  export TEST_BROWSER_HEADLESS=1

  install_standalone_servers

  local _xpack_dir="$(cd x-pack; pwd)"
  echo_info "-> XPACK_DIR ${_xpack_dir}"
  cd "$_xpack_dir"

  varcfg="Glb_${testGrp}Cfg"
  cfgs=${!varcfg}

  nodeOpts=" "
  if [ ! -z $NODE_TLS_REJECT_UNAUTHORIZED ] && [[ $NODE_TLS_REJECT_UNAUTHORIZED -eq 0 ]]; then
    nodeOpts="--no-warnings "
  fi

  failures=0
  for i in $(seq 1 1 $maxRuns); do
    for cfg in $cfgs; do
      if [ $cfg == "test/functional/config.js" ] && [ $funcTests == "false" ]; then
        continue
      fi
      if [ ! -f $cfg ]; then
        echo "Warning invalid configuration: $cfg"
        continue
      fi
      export ESTF_RUN_NUMBER=$i
      update_report_name $cfg

      echo " -> Running standalone xpack ext tests config: $cfg, run $i of $maxRuns"
      node $nodeOpts ../scripts/functional_test_runner \
        --config $cfg \
        --debug
      if [ $? -ne 0 ]; then
        failures=1
      fi
    done
  done

  run_ci_cleanup

  exit_script $failures "Standalone X-Pack Ext Test failed!"
}

# *****************************************************************************
# SECTION: Test grouping functions
# *****************************************************************************

# -----------------------------------------------------------------------------
# Method to use basic license instead of oss
# -----------------------------------------------------------------------------
function remove_oss() {
  local label=""
  if [[ "$Glb_OS" = "darwin" ]]; then
    label=".bak"
  fi
  sed -i $label "s/license: 'oss'/license: 'basic'/g" test/common/config.js
  sed -i $label '/--oss/d' test/new_visualize_flow/config.ts
  sed -i $label '/--oss/d' test/functional/config.js
}

# -----------------------------------------------------------------------------
# Method to update config file with files to be included
# -----------------------------------------------------------------------------
function update_config_file() {
  local testGrp=$1
  local configFile=$2

  if [ -z "$testGrp" ] || [ -z $configFile ] ; then
    return
  fi

  if [ ! -f $configFile ]; then
    return
  fi

  awk -v beg='testFiles: \\[' \
      -v end='\\],' \
      'NR==FNR{new = new $0 ORS; next} $0~end{f=0} !f{print} $0~beg{printf "%s", new; f=1} ' \
      <(echo "${testGrp}") $configFile  > temp.config && mv temp.config $configFile
}

# -----------------------------------------------------------------------------
# Method to group kibana tests, must be from testFiles in config
# -----------------------------------------------------------------------------
function update_config() {
  local configFile=$1
  local testGrp=$2

  if [ -z "$testGrp" ]; then
    return
  fi

  read testGrp tag < <(parse_str $testGrp)

  tmp=$(join_by \| ${!testGrp})
  testGrp=$(awk '$0~/resolve.*apps.*('"$tmp"''\''\),)/{printf "%s\n",$0}' $configFile)

  update_config_file "$testGrp" $configFile

  echo $(get_tags "${!tag}")
}

# -----------------------------------------------------------------------------
# Method to update report name when looping
# -----------------------------------------------------------------------------
function update_report_name() {
  local configFile=$1

  if [ -z $configFile ] ; then
    return
  fi

  if [ ! -f $configFile ]; then
    return
  fi

  local label=""
  if [[ "$Glb_OS" = "darwin" ]]; then
    label=".bak"
  fi

  hasReportName=$(grep -c "reportName" $configFile)
  if [[ $hasReportName == 0 ]]; then
    importCfg=$(grep "createTestConfig.*from" $configFile | grep -Eo "'.*'" | tr -d "'")
    if [[ -z $importCfg ]]; then
      return
    fi
    otherCfg="$(dirname $configFile)/$importCfg.ts"
    if [[ ! -f $otherCfg ]]; then
      return
    fi
    configFile=$otherCfg
  fi

  file_modified=$(grep -c "ESTF_RUN_NUMBER" $configFile)
  echo_debug "$configFile already modified: $file_modified"
  if [[ $file_modified == 0 ]]; then
    brace=$(grep -Ec "reportName.*}," $configFile)
    if [[ $brace > 0 ]]; then
      sed -i $label '/reportName:.*/ s/},/ + process.env.ESTF_RUN_NUMBER},/' $configFile
    else
      sed -i $label '/reportName:.*/ s/,/ + process.env.ESTF_RUN_NUMBER,/' $configFile
    fi
  fi
}

# -----------------------------------------------------------------------------
# Method to update disable_security_user
# -----------------------------------------------------------------------------
function disable_security_user() {
  local configFile="test/functional/config.js"

  file_modified=$(grep -c "disableTestUser" $configFile)
  echo "$configFile already modified: $file_modified"
  if [[ $file_modified == 0 ]]; then
    sed -ri "/\s+security:.*/a \      disableTestUser: true," $configFile
    echo $?
  fi

}

# -----------------------------------------------------------------------------
# Method to update test files
# -----------------------------------------------------------------------------
function update_test_files() {
  local label=""
  if [[ "$Glb_OS" = "darwin" ]]; then
    label=".bak"
  fi
  IFS='
  '
  for item in $ESTF_FLAKY_TEST_SUITE
  do
    testFile=$(get_test_file $item)
    echo_debug $testFile
    git diff --exit-code -s $testFile
    file_modified=$?
    echo_debug "$testFile already modified: $file_modified"
    if [[ $file_modified == 0 ]]; then
      sed -i $label '0,/describe(/ s/describe(/describe\.only(/' $testFile
    fi
  done
}

# -----------------------------------------------------------------------------
# Method to get tag substring, must be after group name, start with Tag til end
# ex: basicGrp1TagSomething
# -----------------------------------------------------------------------------
function parse_str() {
  local testGrp=$1
  local tagStr="Tag"

  rest=${testGrp#*$tagStr}
  if [ $rest == $testGrp ]; then
    echo $testGrp
    return
  fi

  strLen=$(( ${#testGrp} ))
  tagInd=$(( ${#testGrp} - ${#rest} - 3 ))

  grp=${testGrp:0:$tagInd}
  tag=${testGrp:$tagInd:$strLen}

  echo "$grp $tag"
}

# -----------------------------------------------------------------------------
# Method to get tags
# -----------------------------------------------------------------------------
function get_tags() {
  local tags=$1

  if [ -z "$tags" ]; then
    return
  fi

  arr=($tags)
  count=0
  for tag in ${arr[@]}; do
    arr[$count]="--include-tag $tag"
    count=$((count+1))
  done

  echo ${arr[@]}
}

# -----------------------------------------------------------------------------
# Method to join a string by a delimiter
# -----------------------------------------------------------------------------
function join_by {
  local IFS="$1"
  shift
  echo "$*"
}

# -----------------------------------------------------------------------------
# Random docker image testing
# -----------------------------------------------------------------------------
function random_docker_image() {
  arr[0]="default"
  arr[1]="ubi8"

  rand=$[ $RANDOM % 2 ]
  echo ${arr[$rand]}
}

# -----------------------------------------------------------------------------
# Method wait for elasticsearch server to be ready
# -----------------------------------------------------------------------------
function _wait_for_es_ready_logs() {
  while true; do
    sudo tail /var/log/elasticsearch/elasticsearch.log | grep -E -i -w '(to \[GREEN\].*elasticsearch)|(Node.*started)'
    if [ $? -eq 0 ]; then
      break
    fi
    sleep 5;
  done
}

# -----------------------------------------------------------------------------
# Method wait for elasticsearch server to be ready
# -----------------------------------------------------------------------------
function wait_for_es_ready_logs() {
  local timeout=${1:-40}
  run_with_timeout _wait_for_es_ready_logs $timeout
  if [ $? -ne 0 ]; then
    echo_error_exit "Elasticsearch server not ready"
  fi
}

# -----------------------------------------------------------------------------
# Method wait for kibana server to be ready
# -----------------------------------------------------------------------------
function _wait_for_kbn_ready_logs() {
  sleep 15;
  while true; do
    sudo tail -n 30 /var/log/kibana/kibana.log | grep -E -i -w 'kibana.*Server running at'
    if [ $? -eq 0 ]; then
      break
    fi
    sleep 5;
  done
}

# -----------------------------------------------------------------------------
# Method wait for kibana server to be ready
# -----------------------------------------------------------------------------
function wait_for_kbn_ready_logs() {
  local timeout=${1:-90}
  run_with_timeout _wait_for_kbn_ready_logs $timeout
  if [ $? -ne 0 ]; then
    echo_error_exit "Kibana server not ready"
  fi
}

# -----------------------------------------------------------------------------
# Random package testing
# -----------------------------------------------------------------------------
function set_linux_package() {
  local _platform=$1
  local _grp=$2

  if [[ "$_platform" == "docker" ]]; then
    export ESTF_TEST_PACKAGE="docker"
    return
  elif [[ "$_platform" != "linux" ]]; then
    return
  fi

  get_build_server
  get_version
  get_os

  local _splitStr=(${Glb_Kibana_Version//./ })
  local _version=${_splitStr[0]}.${_splitStr[1]}
  local _isPkgSupported=$(vge $_version "7.11")

  if [[ $_isPkgSupported == 0 ]] || [[ "$Glb_Arch" == "aarch64" ]]; then
    export ESTF_TEST_PACKAGE="tar.gz"
    return
  fi

  if [ $_grp == "basicGrp1" ] ||  [ $_grp == "xpackGrp1" ]; then
    export ESTF_TEST_PACKAGE="tar.gz"
    return
  fi

  # TODO: need sudo enable on Jenkins
    export ESTF_TEST_PACKAGE="tar.gz"
    return
  # -- remove once done

  rpmSupported=$(which rpm &>/dev/null; echo $?)
  dpkgSupported=$(which dpkg &>/dev/null; echo $?)

  if [ $rpmSupported -eq 0 ]; then
    export ESTF_TEST_PACKAGE="rpm"
  elif [ $dpkgSupported -eq 0 ]; then
    export ESTF_TEST_PACKAGE="deb"
  else
    export ESTF_TEST_PACKAGE="tar.gz"
  fi
}

# -----------------------------------------------------------------------------
# add_gpg_key
# -----------------------------------------------------------------------------
function add_gpg_key() {
  echo_info "Add GPG Key"
  if [ "$ESTF_TEST_PACKAGE" = "rpm" ]; then
    sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
  else
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Add GPG key failed!"
  fi
}

# -----------------------------------------------------------------------------
# download_elasticsearch_pkg
# -----------------------------------------------------------------------------
function download_elasticsearch_pkg() {
  local _esPkgName="$Glb_Install_Dir/${Glb_Es_Url##*/}"
  local _kbnPkgName="$Glb_Install_Dir/${Glb_Kibana_Url##*/}"

  echo_info "Download Elasticsearch: $Glb_Es_Url"
  curl --silent -o $_esPkgName $Glb_Es_Url
  if [ $? -ne 0 ]; then
    echo_error_exit "Download Elasticsearch failed"
  fi
}

# -----------------------------------------------------------------------------
# install_elasticsearch_pkg
# -----------------------------------------------------------------------------
function install_elasticsearch_pkg() {
  echo_info "Install elasticsearch dir: $Glb_Install_Dir"
  local _esPkgName="$Glb_Install_Dir/${Glb_Es_Url##*/}"
  local _kbnPkgName="$Glb_Install_Dir/${Glb_Kibana_Url##*/}"

  echo_info "Install Elasticsearch Package: $_esPkgName"
  if [ "$ESTF_TEST_PACKAGE" = "rpm" ]; then
    sudo rpm --install $_esPkgName
  else
    sudo dpkg -i $_esPkgName
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Install Elasticsearch failed"
  fi
}

# -----------------------------------------------------------------------------
# download_kibana_pkg
# -----------------------------------------------------------------------------
function download_kibana_pkg() {
  local _esPkgName="$Glb_Install_Dir/${Glb_Es_Url##*/}"
  local _kbnPkgName="$Glb_Install_Dir/${Glb_Kibana_Url##*/}"

  echo_info "Download Kibana: $Glb_Kibana_Url"
  curl --silent -o $_kbnPkgName $Glb_Kibana_Url
  if [ $? -ne 0 ]; then
    echo_error_exit "Download Kibana failed"
  fi
}

# -----------------------------------------------------------------------------
# install_kibana_pkg
# -----------------------------------------------------------------------------
function install_kibana_pkg() {
  echo_info "Install kibana dir: $Glb_Install_Dir"
  local _esPkgName="$Glb_Install_Dir/${Glb_Es_Url##*/}"
  local _kbnPkgName="$Glb_Install_Dir/${Glb_Kibana_Url##*/}"

  echo_info "Install Kibana Package: $_kbnPkgName"
  if [ "$ESTF_TEST_PACKAGE" = "rpm" ]; then
    sudo rpm --install $_kbnPkgName
  else
    sudo dpkg -i $_kbnPkgName
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Install Kibana failed"
  fi
}

# -----------------------------------------------------------------------------
# update_kibana_settings
# -----------------------------------------------------------------------------
function update_kibana_settings() {
  local type=${TEST_KIBANA_BUILD:-basic}

  echo_info "Update Kibana settings"
  if [ "$type" == "basic" ]; then
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/settings/basic/kibana.yml --output kibana.yml
  else
    curl -s https://raw.githubusercontent.com/elastic/elastic-stack-testing/${Glb_Kibana_Branch}/ci/kibana/settings/kibana.yml --output kibana.yml
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Download Kibana settings failed"
  fi

  cat kibana.yml | sudo -s tee -a /etc/kibana/kibana.yml

}

# -----------------------------------------------------------------------------
# elasticsearch_generate_certs
# -----------------------------------------------------------------------------
function elasticsearch_generate_certs() {
  local _esHome="/etc/elasticsearch"
  local _kbnHome="/etc/kibana"
  local _ip=$(hostname -I | sed 's/ *$//g')
  local _isNewCertUtils=$(vge $_version "8.0")

  echo_info "Generate Elasticsearch certificates"

  echo "instances:" > instances.yml
  echo "  - name: escluster" >> instances.yml
  echo "    ip:" >> instances.yml
  echo "      - $_ip" >> instances.yml

   if [[ $_isNewCertUtils == 1 ]]; then

    sudo -s /usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --pem --pass password --out "$_esHome/cabundle.zip"
    if [ $? -ne 0 ]; then
      echo_error_exit "elasticearch-certgen ca failed!"
    fi

    sudo unzip $_esHome/cabundle.zip -d $_esHome
    if [ $? -ne 0 ]; then
      echo_error_exit "Extract ca bundle failed!"
    fi

    sudo -s /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --pem --ca-key "$_esHome/ca/ca.key" --ca-cert  "$_esHome/ca/ca.crt" --ca-pass password --in "$(pwd)/instances.yml" --out "$_esHome/certsbundle.zip"
    if [ $? -ne 0 ]; then
      echo_error_exit "elasticearch-certgen failed!"
    fi

    sudo unzip $_esHome/certsbundle.zip -d $_esHome
    if [ $? -ne 0 ]; then
      echo_error_exit "Extract certs bundle failed!"
    fi

  else

    sudo -s /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --pem  --in "$(pwd)/instances.yml" --out "$_esHome/certsbundle.zip"
    if [ $? -ne 0 ]; then
      echo_error_exit "elasticearch-certgen failed!"
    fi

    sudo unzip $_esHome/certsbundle.zip -d $_esHome
    if [ $? -ne 0 ]; then
      echo_error_exit "Extract certs bundle failed!"
    fi

  fi

  sudo cp -r $_esHome/escluster $_esHome/ca $_kbnHome


sudo -s tee -a /etc/elasticsearch/elasticsearch.yml <<- EOM
network.host: $_ip
discovery.type: single-node
xpack.security.enabled: true
xpack.license.self_generated.type: trial
xpack.security.http.ssl.enabled: true
xpack.security.authc.token.enabled: false
xpack.security.http.ssl.key: $_esHome/escluster/escluster.key
xpack.security.http.ssl.certificate: $_esHome/escluster/escluster.crt
xpack.security.http.ssl.certificate_authorities: [ '$_esHome/ca/ca.crt' ]
EOM

}

# -----------------------------------------------------------------------------
# elasticsearch_setup_passwords
# -----------------------------------------------------------------------------
function elasticsearch_setup_passwords() {
  local _kbnHome="/etc/kibana"
  local _ip=$(hostname -I | sed 's/ *$//g')

  echo_info "Setup passwords"
  echo "y" | sudo -s /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto  | tee passwords.txt
  if [ $? -ne 0 ]; then
    echo_error_exit "Elastisearch setup passwords failed!"
  fi

  espw=$(cat passwords.txt | grep "PASSWORD elastic = " | awk '{print $4}')
  kbnpw=$(cat passwords.txt | grep "PASSWORD kibana = " | awk '{print $4}')

sudo -s tee -a /etc/kibana/kibana.yml <<- EOM
server.host: $_ip
elasticsearch.hosts: "https://${_ip##*( )}:9200"
elasticsearch.username: kibana
elasticsearch.password: $kbnpw
server.ssl.enabled: true
server.ssl.certificate: $_kbnHome/escluster/escluster.crt
server.ssl.key: $_kbnHome/escluster/escluster.key
elasticsearch.ssl.certificateAuthorities: [ '$_kbnHome/ca/ca.crt' ]
elasticsearch.ssl.verificationMode: none
EOM

  export TEST_KIBANA_HOSTNAME=$_ip
  export TEST_KIBANA_PROTOCOL=https
  export TEST_KIBANA_PORT=5601
  export TEST_KIBANA_USER=elastic
  export TEST_KIBANA_PASS=$espw

  export TEST_ES_HOSTNAME=$_ip
  export TEST_ES_PROTOCOL=https
  export TEST_ES_PORT=9200
  export TEST_ES_USER=elastic
  export TEST_ES_PASS=$espw

  export NODE_TLS_REJECT_UNAUTHORIZED=0
  export TEST_IGNORE_CERT_ERRORS=1

}

# -----------------------------------------------------------------------------
# start_elasticsearch_service
# -----------------------------------------------------------------------------
function start_elasticsearch_service() {
  local syssvc=$(ps -p 1)

  echo_info "Start Elasticsearch service"
  if [[ "$syssvc" = *"systemd"* ]]; then
    sudo /bin/systemctl daemon-reload
    sudo /bin/systemctl enable elasticsearch.service
    sudo /bin/systemctl start elasticsearch.service
  else
    sudo -i service elasticsearch start
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Starting elasticsearch service failed"
  fi
  echo_info "Wait for elasticsearch to be ready"
  wait_for_es_ready_logs
}

# -----------------------------------------------------------------------------
# start_kibana_service
# -----------------------------------------------------------------------------
function start_kibana_service() {
  local syssvc=$(ps -p 1)

  echo_info "Start Kibana service"
  if [[ "$syssvc" = *"systemd"* ]]; then
    sudo /bin/systemctl daemon-reload
    sudo /bin/systemctl enable kibana.service
    sudo /bin/systemctl start kibana.service
  else
    sudo -i service kibana start
  fi
  if [ $? -ne 0 ]; then
    echo_error_exit "Starting kibana service failed"
  fi
  echo_info "Wait for kibana to be ready"
  wait_for_kbn_ready_logs
}

# -----------------------------------------------------------------------------
# Install debian packages for elasticsearch and kibana
# -----------------------------------------------------------------------------
function install_packages() {
  local type=${TEST_KIBANA_BUILD:-basic}

  if [ "$ESTF_TEST_PACKAGE" != "rpm" ] && [ "$ESTF_TEST_PACKAGE" != "deb" ]; then
    echo_error_exit "Invalid pkg: $ESTF_TEST_PACKAGE"
  fi

  create_install_dir
  get_build_server
  get_version
  get_os
  get_branch
  get_kibana_pkg
  get_kibana_url
  set_java_home

  add_gpg_key

  download_elasticsearch_pkg
  install_elasticsearch_pkg

  download_kibana_pkg
  install_kibana_pkg

  if [ "$type" != "basic" ]; then
    elasticsearch_generate_certs
  fi

  start_elasticsearch_service

  if [ "$type" != "basic" ]; then
    elasticsearch_setup_passwords
  fi

  update_kibana_settings

  start_kibana_service

  if [ "$type" == "basic" ]; then
    export TEST_KIBANA_PROTOCOL=http
    export TEST_KIBANA_PORT=5601
    export TEST_ES_PROTOCOL=http
    export TEST_ES_PORT=9200
  fi

}

# ----------------------------------------------------------------------------
# Install standalone servers
# ----------------------------------------------------------------------------
function install_standalone_servers() {
  local type=${TEST_KIBANA_BUILD:-basic}

  if [ "$ESTF_TEST_PACKAGE" = "docker" ]; then
    if [ "$type" != "basic" ]; then
      TEST_KIBANA_BUILD=$(random_docker_image)	
    fi
    docker_load
  elif [ "$ESTF_TEST_PACKAGE" = "deb" ] || [ "$ESTF_TEST_PACKAGE" = "rpm" ]; then
    install_packages
  else
    echo_error_exit "Invalid ESTF_TEST_PACKAGE: $ESTF_TEST_PACKAGE"
  fi
}

# ****************************************************************************
# SECTION: Cloud/Docker Configurations
# ****************************************************************************

Glb_xpackExtGrp1Cfg="test/api_integration/config.js
                     test/api_integration/config.ts
                     test/apm_api_integration/trial/config.ts
                     test/functional_enterprise_search/without_host_configured.config.ts
                     test/reporting/configs/chromium_api.js
                     test/reporting/configs/chromium_functional.js
                     test/reporting_api_integration/config.js
                     test/reporting_api_integration/reporting_and_security.config.ts
                    "
Glb_xpackExtGrp2Cfg="test/detection_engine_api_integration/security_and_spaces/config.ts
                     test/ingest_manager_api_integration/config.ts
                     test/security_api_integration/session_idle.config.ts
                     test/security_solution_endpoint/config.ts
                     test/security_solution_endpoint_api_int/config.ts
                    "

Glb_xpackExtAllCfg="$Glb_xpackExtGrp1Cfg
                    $Glb_xpackExtGrp2Cfg
                   "
readonly Glb_xpackExtGrp1Cfg
readonly Glb_xpackExtGrp2Cfg
readonly Glb_xpackExtAllCfg

# ****************************************************************************
# SECTION: Argument parsing and execution
# ****************************************************************************

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo_error_exit "Usage: ./jenkins_kibana_tests.sh <test> or <platform> <test_group>"
fi

if [ $# -eq 1 ]; then
  TEST_GROUP=$1
else
  PLATFORM=$1
  TEST_GROUP=$2
  validPlatforms="cloud darwin linux windows docker"
  isValidPlatform=$(echo $validPlatforms | grep $PLATFORM)
  if [ $? -ne 0 ]; then
    echo_error_exit "Invalid platform '$PLATFORM' must be one of: '$validPlatforms'"
  fi
fi

# -- Set to true, if Chromedriver mismatch on workers
Glb_ChromeDriverHack=false
Glb_YarnNetworkTimeout=0

# Source pre-defined groups
source ./group_defs.sh

# set GCS_UPLOAD_PREFIX env
export GCS_UPLOAD_PREFIX="internal-ci-artifacts/jobs/${JOB_NAME}/${BUILD_NUMBER}"

# Set linux package
set_linux_package $PLATFORM $TEST_GROUP

case "$TEST_GROUP" in
  intake)
    if [ $PLATFORM == "cloud" ] || [ $PLATFORM == "docker" ]; then
      echo_error_exit "'intake' job is not valid on cloud or docker"
    fi
    run_unit_tests
    ;;
  basicGrp*)
    if [ $PLATFORM == "cloud" ]; then
      run_cloud_basic_tests $TEST_GROUP
    elif [ ! -z  $ESTF_TEST_PACKAGE ] && [ $ESTF_TEST_PACKAGE != "tar.gz" ]; then
      run_standalone_basic_tests $TEST_GROUP
    else
      run_basic_tests $TEST_GROUP
    fi
    ;;
  xpackIntake)
    if [ $PLATFORM == "cloud" ] || [ $PLATFORM == "docker" ]; then
      echo_error_exit "'x-pack-intake' job is not valid on cloud or docker"
    fi
    run_xpack_unit_tests
    ;;
  xpackGrp*)
    if [ $PLATFORM == "cloud" ]; then
      run_cloud_xpack_func_tests $TEST_GROUP
    elif [ ! -z  $ESTF_TEST_PACKAGE ] && [ $ESTF_TEST_PACKAGE != "tar.gz" ]; then
      run_standalone_xpack_func_tests $TEST_GROUP
    else
      run_xpack_func_tests $TEST_GROUP
    fi
    ;;
  xpackExt*)
    if [ $PLATFORM == "cloud" ]; then
      run_cloud_xpack_ext_tests $TEST_GROUP
    elif [ ! -z  $ESTF_TEST_PACKAGE ] && [ $ESTF_TEST_PACKAGE != "tar.gz" ]; then
      run_standalone_xpack_ext_tests $TEST_GROUP
    else
      run_xpack_ext_tests false $TEST_GROUP
    fi
    ;;
  selenium)
    run_basic_tests
    ;;
  xpack)
    run_xpack_ext_tests true
    ;;
  unit)
    run_unit_tests
    ;;
  cloud_selenium)
    run_cloud_basic_tests
    ;;
  cloud_xpack)
    run_cloud_xpack_ext_tests true
    ;;
  visual_tests_basic)
    run_visual_tests_basic
    ;;
  visual_tests_default)
    run_visual_tests_default
    ;;
  flaky_test_runner_cloud_prechecks)
    flaky_test_runner_cloud_prechecks
    ;;
  flaky_test_runner)
    flaky_test_runner
    ;;
  build_docker)
    run_ci_setup_get_docker_images
    ;;
  pr_cloud_prechecks)
    pr_cloud_prechecks
    ;;
  *)
    echo_error_exit "TEST_GROUP '$TEST_GROUP' is invalid group"
    ;;
esac
