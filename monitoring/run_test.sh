#!/bin/bash

# stop test if any of the steps fail -x
set -ax

function help() {
    echo "
    Usage run_test.sh -t <path to test spec> -s <server url> [-h]
    "
}

function validate() {
    if [ -z $1 ] ; then
      help
      exit 1
    fi
    if [ -z $2 ]; then
      help
      exit 1
    fi
}


function run_artillery() {
  test_file=$1
  server_url=$2
  container_id=$( \
      docker run \
         -d -it \
         --env SERVER_URL=$server_url \
         --env DEBUG=http*,plugin:expect \
         --env ARTILLERY_PLUGIN_PATH="/plugins" \
         --entrypoint "/bin/sh" \
         renciorg/artillery:2.0.0-5-expect-plugin
      )

  # Copy files
  docker cp "${PWD}/test-specs/${test_file}" $container_id:/test.yaml
  docker cp "${PWD}/test-specs/data/" $container_id:/data/
#  docker cp "${PWD}/test-specs/plugins" $container_id:/plugins/

  docker exec $container_id  artillery run --output /report.json /test.yaml > test_output.yaml
  has_error=$?
  docker exec $container_id  artillery report --output /report.html /report.json
  docker cp $container_id:/report.html "report.html"
  docker cp $container_id:/report.json "report.json"

  if grep -i "errors.enotfound" test_output.yaml; then
    echo "server address ${server_url} not found"
    docker rm -f $container_id
    exit 1
  fi
  if grep -i "errors.etimedout" test_output.yaml; then
    echo "server address ${server_url} timed out in a test"
    docker rm -f $container_id
    exit 1
  fi


  if [ $has_error -eq 1 ]; then
    echo "error found check reports"
    docker rm -f $container_id
    exit 1
  else
    echo "SUCCESS"
    docker rm -f $container_id
    exit 0
  fi

  docker rm -f $container_id

  exit 0
}


test_spec=""
server=""

while getopts t:s:h option
do
    case "${option}"
        in
        t)test_spec=${OPTARG};;
        s)server=${OPTARG};;
        h)help
    esac
done

validate $test_spec $server

run_artillery $test_spec $server