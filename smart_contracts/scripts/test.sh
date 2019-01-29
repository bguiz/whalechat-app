#!/bin/bash

set -e
set -x

set -o errexit
trap cleanup EXIT

cleanup() {
  if [ -n "$ganache_pid" ] && ps -p $ganache_pid > /dev/null; then
    kill -9 $ganache_pid
  fi
}

node_modules/.bin/ganache-cli --gasLimit 0xfffffffffff --accounts 10 > /dev/null &
ganache_pid=$!
sleep 2

truffle=./node_modules/.bin/truffle
$truffle test 
