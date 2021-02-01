#!/bin/bash
set -eu

# check input params, s3cmd config, installed dependencies
if [ -z "$*" ]; then echo "Usage: s3cleanup.sh ORG SPACE SERVICE_NAME"; exit 1; fi
if [ -f $HOME/.s3cfg ]; then echo "s3cmd config $HOME/.s3cfg already exists, please rename/move. Aborting."; exit 1; fi
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

read -p "Is your s3 instance reachable from where this script is executed (y/n)?" choice
case "$choice" in 
  y|Y ) echo "Continuing without cf ssh tunnel";;
  n|N ) echo "Setting port for cf ssh forwarding in generated config" && port=":4443";;
  * ) echo "invalid";;
esac

#heredoc to create s3cmd config in the users homedir
echo "Creating $HOME/.s3cfg" && cat << EOF > $HOME/.s3cfg
[default]
access_key = $access_key
host_base = "$host_base$port"
host_bucket = "$host_bucket$port"
secret_key = $secret_key
EOF

#delete all buckets
echo "Trying to delete all files/buckets on $service."
#s3cmd ls|awk '{print $3}' | while read bucket; do #loop through buckets
#  s3cmd del --recursive $bucket --force || echo "Error deleting the files on the bucket." #delete bucket content 
#  s3cmd rb $bucket || echo "Error removing the bucket itself." #remove actual bucket
#done
#rm $HOME/.s3cfg

echo "Removing temporary service key."
cf delete-service-key $service tempkey -f

[ ! -z "$port" ] && echo "IMPORTANT: Use \"cf ssh -L 4443:$host_base:443 APPNAME\" to connect to any app in your Cloud Foundry to forward the S3 port." 
[ ! -z "$port" ] && echo "IMPORTANT: Add \"127.0.0.1 $host_base\" to your /etc/hosts to be able to connect using the generated $HOME/.s3cfg config." 
echo ""
echo "You can now try to delete your s3 instance. This will only work if no remaining service keys/service shares exist."
echo "Command: cf delete-service $service"
