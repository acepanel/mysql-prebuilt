#!/bin/bash

channel=${1}
slug=${2}
version=${3}
mysql_path="/opt/ace/server/mysql"

echo "Building ${channel} ${version}"

# 准备目录
rm -rf ${mysql_path}
mkdir -p ${mysql_path}
cd ${mysql_path}

# 下载源码
if [[ ${channel} == "mysql" ]]; then
    git clone --depth 1 --branch "mysql-${version}" https://github.com/mysql/mysql-server.git src
elif [[ ${channel} == "percona" ]]; then
    git clone --depth 1 --branch "Percona-Server-${version}" https://github.com/percona/percona-server.git src
elif [[ ${channel} == "mariadb" ]]; then
    git clone --depth 1 --branch "mariadb-${version}" https://github.com/mariadb/server.git src
else
    echo "Unknown channel: ${channel}"
    exit 1
fi

cd src
git submodule init
git submodule update

# 编译
mkdir build
cd build

# 57 和 80 需要 boost 和禁用 TOKUDB
if [[ ${slug} == "57" ]] || [[ ${slug} == "80" ]]; then
    WITH_BOOST="-DDOWNLOAD_BOOST=1 -DWITH_BOOST=${mysql_path}/src/boost"
fi
MAX_INDEXES=255
# MariaDB 只能设置 128
[[ ${channel} == "mariadb" ]] && MAX_INDEXES=128
WITH_SYSTEMD=1
# MariaDB 要使用 yes
[[ ${channel} == "mariadb" ]] && WITH_SYSTEMD="yes"

# 配置编译选项
# INSTALL_SYSCONFDIR 和 PLUGIN_ 是 MariaDB 特有选项
cmake -G Ninja .. \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_INSTALL_PREFIX=${mysql_path} \
    -DMYSQL_DATADIR=${mysql_path}/data \
    -DSYSCONFDIR=${mysql_path}/conf \
    -DINSTALL_SYSCONFDIR=${mysql_path}/conf \
    -DWITH_MYISAM_STORAGE_ENGINE=1 \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_ARCHIVE_STORAGE_ENGINE=0 \
    -DWITH_EXAMPLE_STORAGE_ENGINE=0 \
    -DWITH_FEDERATED_STORAGE_ENGINE=0 \
    -DWITH_BLACKHOLE_STORAGE_ENGINE=0 \
    -DWITH_PARTITION_STORAGE_ENGINE=0 \
    -DWITH_NDBCLUSTER_STORAGE_ENGINE=0 \
    -DPLUGIN_CONNECT=NO \
    -DPLUGIN_COLUMNSTORE=NO \
    -DPLUGIN_SPHINX=NO \
    -DPLUGIN_SPIDER=NO \
    -DPLUGIN_S3=NO \
    -DPLUGIN_ARCHIVE=NO \
    -DPLUGIN_BLACKHOLE=NO \
    -DPLUGIN_FEDERATED=NO \
    -DPLUGIN_FEDERATEDX=NO \
    -DPLUGIN_EXAMPLE=NO \
    -DPLUGIN_PARTITION=NO \
    -DPLUGIN_PERFSCHEMA=NO \
    -DPLUGIN_MROONGA=NO \
    -DPLUGIN_ROCKSDB=NO \
    -DWITH_TOKUDB=0 \
    -DWITH_ROCKSDB=0 \
    -DDEFAULT_CHARSET=utf8mb4 \
    -DDEFAULT_COLLATION=utf8mb4_general_ci \
    -DMAX_INDEXES=${MAX_INDEXES} \
    -DWITH_RAPID=0 \
    -DWITH_NDBMTD=0 \
    -DENABLED_LOCAL_INFILE=1 \
    -DWITH_COREDUMPER=0 \
    -DWITH_BUILD_ID=0 \
    -DWITH_DEBUG=0 \
    -DWITH_UNIT_TESTS=OFF \
    -DINSTALL_MYSQLTESTDIR= \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_SYSTEMD=${WITH_SYSTEMD} \
    -DSYSTEMD_PID_DIR=${mysql_path} \
    -DWITH_EMBEDDED_SERVER=0 \
    -DWITH_EMBEDDED_SHARED_LIBRARY=0 \
    ${WITH_BOOST} \
    -DWITH_MYSQLX=0 \
    -DWITH_ROUTER=0 \
    -DWITH_LTO=1 \
    -DCOMPRESS_DEBUG_SECTIONS=1
if [ "$?" != "0" ]; then
    rm -rf ${mysql_path}
    echo "Compilation initialization failed"
    exit 1
fi

ninja
if [ "$?" != "0" ]; then
    rm -rf ${mysql_path}
    echo "Compilation failed"
    exit 1
fi

# 安装
ninja install
if [ "$?" != "0" ]; then
    rm -rf ${mysql_path}
    echo "Installation failed"
    exit 1
fi

# 清理
cd ${mysql_path}
rm -rf src
rm -rf ${mysql_path}/lib/*.a
rm -rf ${mysql_path}/bin/ldb
rm -rf ${mysql_path}/bin/mysql_ldb
rm -rf ${mysql_path}/bin/sst_dump
rm -rf ${mysql_path}/bin/mysql_client_test*
rm -rf ${mysql_path}/bin/mysqltest*
rm -rf ${mysql_path}/bin/mysql_embedded

# 精简压缩
strip -s ${mysql_path}/bin/*
7z a -m0=lzma2 -ms=on -mx=9 "${channel}-server-${version}.7z" *
if [ "$?" != "0" ]; then
    rm -rf ${mysql_path}
    echo "Packaging failed"
    exit 1
fi

echo "Build successful"
exit 0
