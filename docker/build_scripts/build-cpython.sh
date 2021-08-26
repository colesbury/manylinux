#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
source $MY_DIR/build_utils.sh


CPYTHON_VERSION=$1
CPYTHON_DOWNLOAD_URL=https://www.python.org/ftp/python


function pyver_dist_dir {
	# Echoes the dist directory name of given pyver, removing alpha/beta prerelease
	# Thus:
	# 3.2.1   -> 3.2.1
	# 3.7.0b4 -> 3.7.0
	echo $1 | awk -F "." '{printf "%d.%d.%d", $1, $2, $3}'
}

GIT_TOKEN=$(cat /.git-credentials | cut -d/ -f 3 | cut -d: -f 1)
echo "GIT_TOKEN=$GIT_TOKEN"

CPYTHON_DIST_DIR=$(pyver_dist_dir ${CPYTHON_VERSION})
tag=$2
curl -L --user "$GIT_TOKEN:" https://github.com/colesbury/nogil/tarball/$tag -o nogil.tar.gz
mkdir nogil
tar -xC nogil --strip-components=1 -f nogil.tar.gz
pushd nogil
PREFIX="/opt/_internal/nogil-${CPYTHON_VERSION}"
mkdir -p ${PREFIX}/lib
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ]; then
	# The _ctypes stdlib module build started to fail with 3.10.0rc1
	# No clue what changed exactly yet
	# This workaround fixes the build
	LIBFFI_INCLUDEDIR=$(pkg-config --cflags-only-I libffi  | tr -d '[:space:]')
	LIBFFI_INCLUDEDIR=${LIBFFI_INCLUDEDIR:2}
	cp ${LIBFFI_INCLUDEDIR}/ffi.h ${LIBFFI_INCLUDEDIR}/ffitarget.h /usr/include/
fi
# configure with hardening options only for the interpreter & stdlib C extensions
# do not change the default for user built extension (yet?)
./configure \
	CFLAGS_NODIST="${MANYLINUX_CFLAGS} ${MANYLINUX_CPPFLAGS}" \
	LDFLAGS_NODIST="${MANYLINUX_LDFLAGS}" \
	--prefix=${PREFIX} --disable-shared --with-ensurepip=no > /dev/null
make > /dev/null
make install > /dev/null
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ]; then
	rm -f /usr/include/ffi.h /usr/include/ffitarget.h
fi
popd
rm -rf Python-${CPYTHON_VERSION} Python-${CPYTHON_VERSION}.tgz Python-${CPYTHON_VERSION}.tgz.asc

# we don't need libpython*.a, and they're many megabytes
find ${PREFIX} -name '*.a' -print0 | xargs -0 rm -f

# We do not need precompiled .pyc and .pyo files.
clean_pyc ${PREFIX}

# Strip ELF files found in ${PREFIX}
strip_ ${PREFIX}
