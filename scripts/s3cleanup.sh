#!/bin/bash
set -eu

# check input params, s3cmd config, installed dependencies
if [ -z "$*" ]; then echo "Usage: s3cleanup.sh ORG SPACE SERVICE_NAME"; exit 1; fi
if [ -f $HOME/.s3cfg ]; then echo "s3cmd config $HOME/.s3cfg already exists, please rename temporarily. Aborting."; exit 1; fi
command -v cf >/dev/null 2>&1 || { echo >&2 "cf cli not installed. Aborting."; exit 1; }
command -v s3cmd >/dev/null 2>&1 || { echo >&2 "s3cmd not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq not installed. Aborting."; exit 1; }

#read input params
org=$1
space=$2
service=$3

#change to org/space and create temporary service key
cf t -o $org -s $space
cf csk $service tempkey

#parse s3cmd config from service key
service_key=`cf service-key $service tempkey|tail -n 8`
access_key=`echo $service_key|jq -r .accessKey`
host_base=`echo $service_key|jq -r .namespaceHost|cut -d "." -f 2-4`
host_bucket=`echo $service_key|jq -r .namespaceHost`
secret_key=`echo $service_key|jq -r .sharedSecret`

#heredoc to create s3cmd config in the users homedir
echo "Creating $HOME/.s3cfg" && cat << EOF > $HOME/.s3cfg
[default]
access_key = $access_key
host_base = $host_base
host_bucket = $host_bucket
secret_key = $secret_key
EOF

#delete all buckets
echo "Trying to delete all files/buckets on $service."
s3cmd ls|awk '{print $3}' | while read bucket; do #loop through buckets
  s3cmd del --recursive $bucket --force #delete bucket content
  s3cmd rb $bucket #remove actual bucket
done
rm $HOME/.s3cfg
echo "Finished deleting files/buckets on $service."

echo "Removing temporary service key."
cf delete-service-key $service tempkey -f

echo "You can now try to delete your s3 instance. This will only work if no remaining service keys/service shares exist."
echo "Command: cf delete-service $service"
