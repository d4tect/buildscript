#!/usr/bin/env bash

# Build script for the OpenXeChain toolchain project
#
# Copyright (c) 2025 Aiden Isik
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# The build is split into two stages so a failure after LLVM does not require
# rebuilding LLVM:
#   build-toolchain-stage1.sh: LLVM/Clang/LLD + initial Clang configuration
#   build-toolchain-stage2.sh: xecorelib, Newlib, compiler-rt, SynthXEX
# Both read the same environment variables (PREFIX, HOST_CC, HOST_CXX,
# BUILD_TYPE, PARALLEL). Stage 2 can be re-run on its own as often as needed.

cd "$(dirname $0)" || exit 1
./build-toolchain-stage1.sh || exit 1
./build-toolchain-stage2.sh || exit 1
