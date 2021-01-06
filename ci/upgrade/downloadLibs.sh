#!/bin/bash
# ----------------------------------------------------------------------------------------------------------------------
# Download jars
#
# Author: Liza Dayoub
# ----------------------------------------------------------------------------------------------------------------------

function createLibsDir() {
    if [ ! -d ${libsDir} ]; then
        echo ".. Creating libs directory"
        mkdir ${libsDir}
        if [ $? -ne 0 ]; then
            echo "Error! Unable to create directory"
            exit 1
        fi
    fi
    cd ${libsDir}
}

function downloadCloudSdk() {
    echo ".. Download cloud java sdk"
    local ghOwner="${GH_OWNER:?GH_OWNER needs to be set!}"
    local ghToken="${GH_TOKEN:?GH_TOKEN needs to be set!}"
    local sdkVersion="2.7.0-SNAPSHOT"
    local releaseByTagUrl="https://api.github.com/repos/${ghOwner}/cloud-sdk-java/releases/tags/${sdkVersion}"
    releaseByTagResponse=$(curl -H "Authorization: token ${ghToken}" -s ${releaseByTagUrl})
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get release by tag url"
        exit 1
    fi
    assetName=$(curl -H "Authorization: token ${ghToken}" -s ${releaseByTagUrl} | \
                python -c "import sys, json; print(json.load(sys.stdin)['assets'][0]['name'])")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get asset name"
        exit 1
    fi
    assetUrl=$(curl -H "Authorization: token ${ghToken}" -s ${releaseByTagUrl} | \
               python -c "import sys, json; print(json.load(sys.stdin)['assets'][0]['url'])")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get asset url"
        exit 1
    fi
    downloadResponse=$(curl -L -H "Authorization: token ${ghToken}" \
                            -H "Accept: application/octet-stream" ${assetUrl} -o ${assetName})
    if [ $? -ne 0 ]; then
        echo "Error! Unable to download java sdk"
        exit 1
    fi
}

function downloadVaultDriver() {
    echo ".. Download java vault driver"
    vaultDriver=$(wget "$mavenRepo/com/bettercloud/vault-java-driver/5.1.0/vault-java-driver-5.1.0.jar")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get asset url"
        exit 1
    fi
}

function downloadApacheHttpClientCore() {
    echo ".. Download apache http client and core"
    httpClient=$(wget "$mavenRepo/org/apache/httpcomponents/httpclient/4.5.13/httpclient-4.5.13.jar")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get http client"
        exit 1
    fi
    httpCore=$(wget "$mavenRepo/org/apache/httpcomponents/httpcore/4.4.13/httpcore-4.4.13.jar")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get http core"
        exit 1
    fi
}

function downloadJson() {
    echo ".. Download json"
    json=$(wget "$mavenRepo/org/json/json/20200518/json-20200518.jar")
    if [ $? -ne 0 ]; then
        echo "Error! Unable to get json"
        exit 1
    fi
}

export PYTHONIOENCODING=utf8
mavenRepo="https://repo.maven.apache.org/maven2"
libsDir="buildSrc/libs"

createLibsDir
downloadCloudSdk
downloadVaultDriver
downloadApacheHttpClientCore
downloadJson
