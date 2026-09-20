#!/usr/bin/env bash
# Control: correct spec+test. Guards against a reviewer that FAILs everything.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_lib" && pwd)/base-project.sh"
: # no mutation — the base project is the correct one
