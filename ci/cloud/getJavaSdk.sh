#!/bin/bash

export PYTHONIOENCODING=utf8

libsDir="buildSrc/libs"
ghOwner="${GH_OWNER:?GH_OWNER needs to be set!}"
ghToken="${GH_TOKEN:?GH_TOKEN needs to be set!}"
sdkVersion="1.2.0-SNAPSHOT"

if [ ! -d ${libsDir} ]; then
	echo "Creating libs directory..."
	mkdir ${libsDir}
	echo "Created!"
fi

echo "Download cloud java sdk"
getReleaseByTagUrl="https://api.github.com/repos/${ghOwner}/cloud-sdk-java/releases/tags/v${sdkVersion}"
getReleaseByTagResponse=$(curl -H "Authorization: token ${ghToken}" -s ${getReleaseByTagUrl})
assetName=$(curl -H "Authorization: token ${ghToken}" -s ${getReleaseByTagUrl} | python -c "import sys, json; print(json.load(sys.stdin)['assets'][0]['name'])")
assetUrl=$(curl -H "Authorization: token ${ghToken}" -s ${getReleaseByTagUrl}  | python -c "import sys, json; print(json.load(sys.stdin)['assets'][0]['url'])")
assetUrlWithAuth="${assetUrl}"
downloadResponse=$(curl -L -H "Authorization: token ${ghToken}" -H "Accept: application/octet-stream" ${assetUrlWithAuth} -o ${libsDir}/${assetName})

cd ${libsDir}

echo "Download java vault driver"
wget "https://repo.maven.apache.org/maven2/com/bettercloud/vault-java-driver/5.1.0/vault-java-driver-5.1.0.jar"

echo "Download apache http client"
wget "https://repo.maven.apache.org/maven2/org/apache/httpcomponents/httpclient/4.5.13/httpclient-4.5.13.jar"
wget "https://repo.maven.apache.org/maven2/org/apache/httpcomponents/httpcore/4.4.13/httpcore-4.4.13.jar"

echo "Download json"
wget "https://repo.maven.apache.org/maven2/org/json/json/20200518/json-20200518.jar"

echo "Download snakeyaml"
wget "https://repo1.maven.org/maven2/org/yaml/snakeyaml/1.27/snakeyaml-1.27.jar"
