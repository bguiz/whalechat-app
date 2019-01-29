#!/usr/bin/env bash

ganache_port=8555

# Exit script as soon as a command fails.
set -o errexit

# Executes cleanup function at script exit.
trap cleanup EXIT

cleanup() {
  # Kill the ganache instance that we started (if we started one and if it's still running).
  if [ -n "$ganache_pid" ] && ps -p $ganache_pid > /dev/null; then
    kill -9 $ganache_pid
  fi
}

ganache_running() {
  nc -z localhost "$ganache_port"
}

start_ganache() {
  node_modules/.bin/testrpc-sc --gasLimit 0xfffffffffff --port "$ganache_port" > /dev/null &
  ganache_pid=$!
}

if ganache_running; then
  echo "Using existing ganache instance"
else
  echo "Starting our own ganache instance"
  start_ganache
fi

node_modules/.bin/truffle version
node_modules/.bin/solidity-coverage


