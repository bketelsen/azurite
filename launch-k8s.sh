#!/usr/bin/env bash
set -e

# ---------------- User configuration ----------------

AZURITE_PUBLIC_KEY="${HOME}/.ssh/id_rsa.pub"
AZURITE_PREFIX="k8s"
AZURITE_TEMPLATE_STORE="${HOME}/azure-templates"
AZURITE_LOCATION="eastus"

# ---------------- User configuration ----------------

# Vars
mkdir -p $AZURITE_TEMPLATE_STORE
BIN_DIR=`dirname "$BASH_SOURCE"`
NAME=$(az account show | jq -r .user.name)

# Validate
if [ -z $NAME ]; then
    echo "Please (az login) and try again"
    exit 1
fi

if [ -z $AZURE_SUBSCRIPTION_ID ]; then
    echo "Please export $AZURE_SUBSCRIPTION_ID and try again"
    exit 1
fi

# Begin Kubernetes
echo "Creating a new Kubernetes cluster for [${NAME}]"

# Service Principle Hackery

SPJSON=$(az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/${AZURE_SUBSCRIPTION_ID}")
#SPJSON=$(cat $BIN_DIR/_sp.json)

SP_APP_ID=$(echo ${SPJSON} | jq  -r .appId)
SP_NAME=$(echo ${SPJSON} | jq  -r .name)
SP_PASSWORD=$(echo ${SPJSON} | jq  -r .password)
SP_TENANT=$(echo ${SPJSON} | jq  -r .tenant)

# Generate ID
TMP_FILE=$(mktemp)
ID=$(md5sum ${TMP_FILE} | cut -d " " -f 1)
echo "ID: [${ID}]"

PUBKEY=$(cat ${AZURITE_PUBLIC_KEY})
RANDOM_WORD1=$(curl http://setgetgo.com/randomword/get.php)
RANDOM_WORD2=$(curl http://setgetgo.com/randomword/get.php)
DNS_PREFIX=${AZURITE_PREFIX}-${RANDOM_WORD1}-${RANDOM_WORD2}

# Edit Template
cat ${BIN_DIR}/_kubernetes.json | sed -e "s/password/${SP_PASSWORD}/g" | sed -e "s/appid/${SP_APP_ID}/g" | sed -e "s|pubkey|${PUBKEY}|g" | sed -e "s/prefix/${DNS_PREFIX}/g" > ${TMP_FILE}
${EDITOR} ${TMP_FILE}


cd $AZURITE_TEMPLATE_STORE
acs-engine generate $TMP_FILE

# Create Resource Group
az group create --name "${ID}" --location  "${AZURITE_LOCATION}"

TMP_FILE=$(mktemp)
cat "./_output/${DNS_PREFIX}/azuredeploy.parameters.json" > $TMP_FILE
${EDITOR} ${TMP_FILE}
cat $TMP_FILE > "./_output/${DNS_PREFIX}/azuredeploy.parameters.json"

# Create Deployment
az group deployment create \
    --name "${ID}" \
    --resource-group "${ID}" \
    --template-file "./_output/${DNS_PREFIX}/azuredeploy.json" \
    --parameters "@./_output/${DNS_PREFIX}/azuredeploy.parameters.json"