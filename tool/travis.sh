#!/bin/bash

# Fast fail the script on failures.
set -e

dartanalyzer --fatal-warnings \
  lib/serial_wss_sim.dart \
  bin/serial_wss_sim.dart

pub run test -p vm