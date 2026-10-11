#!/usr/bin/env bash

# Build script for the OpenXeChain toolchain project (stage 1: LLVM/Clang/LLD)
#
# Copyright (c) 2025 Aiden Isik
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# ANSI colour escape codes
ANSI_RED="\033[31m"
ANSI_GRN="\033[32m"
ANSI_CLR="\033[0m"

# Toolchain name
TOOLCHAIN_NAME="OpenXeChain"
TOOLCHAIN_STEM="${ANSI_GRN}${TOOLCHAIN_NAME}${ANSI_CLR}> "

# User-configurable variables
PREFIX="$(realpath ${PREFIX:-sysroot})" # Sysroot for the toolchain to be installed into
HOST_CC="${HOST_CC:-clang}" # Host compiler to use (MUST BE CLANG)
HOST_CXX="${HOST_CXX:-clang++}"
BUILD_TYPE="${BUILD_TYPE:-Release}" # Debug level to build LLVM in
PARALLEL="${PARALLEL:-$(nproc)}" # Number of parallel make jobs to run
LLVM_EXTRA_CMAKE_ARGS="${LLVM_EXTRA_CMAKE_ARGS:-}" # Extra host-side CMake flags for LLVM (e.g. -DLLVM_USE_LINKER=lld)

# Static variables
LLVM_TARGET="ppc32-xbox360"
NEWLIB_TARGET="ppc-xbox360"
OLD_PWD="${PWD}"

# Build log path
BUILD_LOG="${OLD_PWD}/build-stage1.log"
echo "" > "${BUILD_LOG}" # Delete the old logs, if they exist

# If we fail to build, run this
fail_build()
{
    echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Failed to build! Check build.log.${ANSI_CLR}"
    exit 1
}

# Check to make sure all required dependencies are installed
check_deps()
{
    MISSING_DEPS=0

    clang --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing clang!${ANSI_CLR}")

    ar --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing binutils!${ANSI_CLR}")

    git --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing git!${ANSI_CLR}")

    cmake --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing cmake!${ANSI_CLR}")

    make --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing make!${ANSI_CLR}")

    ninja --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing ninja!${ANSI_CLR}")

    python3 --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing python3!${ANSI_CLR}")

    bash --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing bash!${ANSI_CLR}")

    bzip2 --help >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing bzip2!${ANSI_CLR}")

    gzip --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing gzip!${ANSI_CLR}")

    grep --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing grep!${ANSI_CLR}")

    xargs --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing findutils!${ANSI_CLR}")

    sed --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing sed!${ANSI_CLR}")

    tar --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing tar!${ANSI_CLR}")

    unzip --help >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing unzip!${ANSI_CLR}")

    zip -v >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing zip!${ANSI_CLR}")

    gawk --version >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing gawk!${ANSI_CLR}")

    # Zlib cannot be checked like this as it has no binaries, but it should have been installed
    # as a dependency of python3

    # Check for pyyaml with a simple python script
    cat > "test-pyyaml-openxechain.py" << EOF
import importlib.util
pyyaml_test=importlib.util.find_spec('yaml')
if pyyaml_test is None:
        exit(1)
else:
        exit(0)
EOF

    python3 test-pyyaml-openxechain.py >> "${BUILD_LOG}" 2>&1 ||
        (MISSING_DEPS=1 && echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Missing python-pyyaml!${ANSI_CLR}")

    rm -f test-pyyaml-openxechain.py

    if [[ ${MISSING_DEPS} -ne 0 ]]; then
        echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Dependencies are missing! Please install them.${ANSI_CLR}"
    fi

    return ${MISSING_DEPS}
}

cd "$(dirname $0)" || fail_build

if [[ ! -d "newlib" || ! -d "llvm" || ! -d "synthxex" || ! -d "xecorelib" ]]; then
    echo -e "${TOOLCHAIN_STEM}${ANSI_RED}Submodules are missing! Please re-clone this repository with --recursive.${ANSI_CLR}"
    fail_build
fi

# Create the sysroot directory, if it doesn't already exist
echo -e "${TOOLCHAIN_STEM}Creating sysroot directory \"${PREFIX}\"."
mkdir -pv "${PREFIX}" >> "${BUILD_LOG}" 2>&1 || fail_build

# Make sure all required dependencies are installed
echo -e "${TOOLCHAIN_STEM}Checking if required dependencies are installed."
mkdir -pv "build" >> "${BUILD_LOG}" 2>&1 || fail_build
cd "build" || fail_build
check_deps || fail_build

# Configure it first
echo -e "${TOOLCHAIN_STEM}Configuring the cross compiler... (this may take a while)"
cmake -DCMAKE_C_COMPILER="${HOST_CC}" \
      -DCMAKE_CXX_COMPILER="${HOST_CXX}" \
      -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DLLVM_ENABLE_PROJECTS="lld;clang" \
      -DLLVM_TARGETS_TO_BUILD=PowerPC \
      -DLLVM_DEFAULT_TARGET_TRIPLE="${LLVM_TARGET}" \
      -DLLVM_INSTALL_BINUTILS_SYMLINKS=true \
      -DLLVM_INSTALL_CCTOOLS_SYMLINKS=true \
      -DLLVM_INSTALL_TOOLCHAIN_ONLY=true \
      ${LLVM_EXTRA_CMAKE_ARGS} \
      -G "Ninja" ../llvm/llvm >> "${BUILD_LOG}" 2>&1 || fail_build

# Now build and install
echo -e "${TOOLCHAIN_STEM}Building the cross compiler... (this may take a WHILE)"
ninja -j${PARALLEL} >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Installing the cross compiler... (this may take a while)"
ninja install >> "${BUILD_LOG}" 2>&1 || fail_build

echo -e "${TOOLCHAIN_STEM}Cross compiler built and installed!"
rm -rf * # Clear the build directory, ready for xecorelib

# Define the default command line flags to be used by the cross-compiler.
# Linkage to Newlib/xecorelib is also added to these files, but after it's been built and installed.
echo -e "${TOOLCHAIN_STEM}Writing initial Clang configuration scripts."

cat > "${PREFIX}/bin/clang.cfg" << EOF
-Wno-main-return-type
--sysroot=<CFGDIR>/..
--rtlib=compiler-rt
-fdeclspec
-mlongcall
EOF

cat > "${PREFIX}/bin/clang++.cfg" << EOF
-Wno-main-return-type
--sysroot=<CFGDIR>/..
--rtlib=compiler-rt
-fdeclspec
-mlongcall
EOF

# Keep a pristine copy of the initial configuration scripts, so stage 2 can be
# re-run any number of times without rebuilding LLVM.
cp "${PREFIX}/bin/clang.cfg" "${PREFIX}/bin/clang.cfg.stage1" || fail_build
cp "${PREFIX}/bin/clang++.cfg" "${PREFIX}/bin/clang++.cfg.stage1" || fail_build
git -C llvm rev-parse HEAD > "${PREFIX}/.stage1-llvm-commit" 2>/dev/null || true

echo -e "${TOOLCHAIN_STEM}${ANSI_GRN}Stage 1 (LLVM) finished. Run build-toolchain-stage2.sh next.${ANSI_CLR}"

cd ..
rm -rf build
rm -f build-stage1.log
