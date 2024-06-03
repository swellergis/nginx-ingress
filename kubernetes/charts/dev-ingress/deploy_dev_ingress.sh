#!/bin/bash

# Prequisites:
# - Minikube must be running
# - /etc/hosts contains the following line
#   192.168.49.2	auth.local guardian.local logi.local
PROCEED=no
echo -n "This script will DELETE and recreate your ingress TLS certificate and ingress.  Proceed?(y/n): "
read PROCEED

if [ ! "${PROCEED}" == "y" ] ; then
  echo "Exiting.."
  exit 0
fi

# make sure we are using minikube context
kubectl config use-context minikube

# check for and remove existing helm deployment of the dev ingress
HELM_DEPLOYMENT_NAME=dev-apps-ingress
helm list | grep "${HELM_DEPLOYMENT_NAME}"
if [ "$?" -eq 0 ] ; then
  echo "Deleting existing ${HELM_DEPLOYMENT_NAME} helm deployment"
  helm delete ${HELM_DEPLOYMENT_NAME}
fi

# check for and remove existing tls secret
TLS_SECRET_NAME=dev-ingress-secret
kubectl -n dev get -o name secrets |grep "${TLS_SECRET_NAME}"
if [ "$?" -eq 0 ] ; then
  echo "Deleting existing ${TLS_SECRET_NAME} secret"
  kubectl -n dev delete secret ${TLS_SECRET_NAME}
fi

set -e

EXPIRE_DAYS=10650
KEY_BITS=4096
CERTS_DIR="$(pwd)/certs"

COUNTRY=US
STATE=Colorado
TMPSTATE=
LOCALITY=Thornton
TMPLOCALITY=
ORG=Lumen
OU="Government Services"

# prompt for City and State 
while [ "${TMPSTATE}z" == "z" ] ;
do
  echo -n "Enter full state name to go in certificates(e.g. ${STATE}): "
  read TMPSTATE
done
STATE="${TMPSTATE}"

while [ "${TMPLOCALITY}z" == "z" ] ;
do
  echo -n "Enter full city name to go in certificates(e.g. ${LOCALITY}): "
  read TMPLOCALITY
done
LOCALITY="${TMPLOCALITY}"

if [ -d "${CERTS_DIR}" ] ; then
  rm -rf "${CERTS_DIR}"
fi

mkdir  "${CERTS_DIR}"

pushd .

cd "${CERTS_DIR}"

echo "Creating CA"
CA_KEY_FILE=CAPrivate.key
CA_CERT_FILE=CAPrivate.pem
echo
echo "Creating CA private key"
# make CA private key
openssl genrsa -out ${CA_KEY_FILE} 4096

# create the CA cert
echo
echo "Creating CA cert"
openssl req \
	-x509 \
	-new \
	-nodes \
	-key ${CA_KEY_FILE} \
	-sha256 \
	-days ${EXPIRE_DAYS} \
	-out ${CA_CERT_FILE} \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/OU=${OU}/CN=ca.local" \
	-addext "subjectAltName = DNS:ca.local"

COUNTRY=US
STATE=Colorado
LOCALITY=Thornton
ORG=Lumen
OU="Government Services"


#
CSR_FILE=dev-ingress-tls-csr.pem
CERT_FILE=dev-ingress-tls-cert.pem
KEY_FILE=dev-ingress-tls-key.pem

# create cert private key
echo
echo "Creating private key ingress cert request"
openssl genrsa -out ${KEY_FILE} ${KEY_BITS}

# generate the csr
echo
echo "Creating ingress cert request"
openssl req -new -key ${KEY_FILE} -extensions v3_ca -out ${CSR_FILE} \
	-subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG}/OU=${OU}/CN=*.local" \
	-addext "subjectAltName = DNS:*.local"

echo
echo "Signing ingress cert request"
openssl x509 -req -in ${CSR_FILE} -CA ${CA_CERT_FILE} -CAkey ${CA_KEY_FILE} -CAcreateserial -out ${CERT_FILE} -days ${EXPIRE_DAYS} -sha256

# create secret from the key and cert
echo
echo "Creating secret ${TLS_SECRET_NAME} for from ${KEY_FILE} and ${CERT_FILE}"
kubectl -n dev create secret tls ${TLS_SECRET_NAME} --key ${KEY_FILE} --cert ${CERT_FILE}

echo
echo "Secret ${TLS_SECRET_NAME} details:"
kubectl -n dev describe secret ${TLS_SECRET_NAME}

cd ..

# deploy the ingress
echo
echo "Deploying ${HELM_DEPLOYMENT_NAME} helm deployment" 
helm install ${HELM_DEPLOYMENT_NAME} chart

# show list of ingresses
echo
echo "Currently defined ingresses"
kubectl -n dev get ingresses

echo
echo "Ingress deployment complete"
echo
echo "Please install the following certificate in your browsers and any application truststores that will need to access via the ingress:"
echo "$(pwd)/certs/${CERT_FILE}"
popd
