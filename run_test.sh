#!/usr/bin/env bash

./zig-out/bin/dummy &
dummy_pid=$!

sudo ./zig-out/bin/heap_read $dummy_pid

kill "$dummy_pid"

