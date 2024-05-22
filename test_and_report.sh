#!/bin/bash


if [ "$1" != "" ]; then
  ./bin/test --procs=4 "$1" -v
else
  ./bin/test --procs=4 -v
fi
./process_logs.sh
./print_status_tree.sh

