#!/bin/bash
# Copyright 2012 Cloudera Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Loads a test-warehouse snapshot file into HDFS. Test-warehouse snapshot files
# are produced as an artifact of each successful master Jenkins build and can be
# downloaded from the Jenkins job webpage.
#
# NOTE: Running this script will remove your existing test-warehouse directory. Be sure
# to backup any data you need before running this script.

. ${IMPALA_HOME}/bin/impala-config.sh > /dev/null 2>&1

if [[ ! $1 ]]; then
  echo "Usage: load-test-warehouse-snapshot.sh [test-warehouse-SNAPSHOT.tar.gz]"
  exit 1
fi

TEST_WAREHOUSE_DIR="/test-warehouse"

set -u
SNAPSHOT_FILE=$1
if [ ! -f ${SNAPSHOT_FILE} ]; then
  echo "Snapshot tarball file '${SNAPSHOT_FILE}' not found"
  exit 1
fi

echo "Your existing ${TARGET_FILESYSTEM} warehouse directory " \
     "(${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}) will be removed."
read -p "Continue (y/n)? "
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  # Create a new warehouse directory. If one already exist, remove it first.
  if [ "${TARGET_FILESYSTEM}" = "s3" ]; then
    # TODO: The aws cli emits a lot of spew, redirect /dev/null once it's deemed stable.
    aws s3 rm --recursive s3://${S3_BUCKET}${TEST_WAREHOUSE_DIR}
    if [ $? != 0 ]; then
      echo "Deleting pre-existing data in s3 failed, aborting."
    fi
  else
    # Either isilon or hdfs, no change in procedure.
    hadoop fs -test -d ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}
    if [ $? -eq 0 ]; then
      echo "Removing existing test-warehouse directory"
      # On Isilon, we run into undiagnosed permission issues. chmod the entire folder to
      # 777 as a workaround.
      if [ "${TARGET_FILESYSTEM}" = "isilon" ]; then
        hadoop fs -chmod -R 777 ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}
      fi
      hadoop fs -rm -r -skipTrash ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}
    fi
    echo "Creating test-warehouse directory"
    hadoop fs -mkdir ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}
  fi
else
  echo -e "\nAborting."
  exit 1
fi

set -e

echo "Loading snapshot file: ${SNAPSHOT_FILE}"
SNAPSHOT_STAGING_DIR=`dirname ${SNAPSHOT_FILE}`/hdfs-staging-tmp
rm -rf ${SNAPSHOT_STAGING_DIR}
mkdir ${SNAPSHOT_STAGING_DIR}

echo "Extracting tarball"
tar -C ${SNAPSHOT_STAGING_DIR} -xzf ${SNAPSHOT_FILE}

if [ ! -f ${SNAPSHOT_STAGING_DIR}/test-warehouse/githash.txt ]; then
  echo "The test-warehouse snapshot does not containa githash, aborting load"
  exit 1
fi


echo "Loading hive builtins"
${IMPALA_HOME}/testdata/bin/load-hive-builtins.sh
echo "Copying data to ${TARGET_FILESYSTEM}"
if [ "${TARGET_FILESYSTEM}" = "s3" ]; then
  # hive does not yet work well with s3, so we won't need hive builtins.
  # TODO: The aws cli emits a lot of spew, redirect /dev/null once it's deemed stable.
  aws s3 cp --recursive ${SNAPSHOT_STAGING_DIR}${TEST_WAREHOUSE_DIR} \
      s3://${S3_BUCKET}${TEST_WAREHOUSE_DIR}
  if [ $? != 0 ]; then
    echo "Copying the test-warehouse to s3 failed, aborting."
  fi
else
  hadoop fs -put ${SNAPSHOT_STAGING_DIR}${TEST_WAREHOUSE_DIR}/* ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}
fi

${IMPALA_HOME}/bin/create_testdata.sh
echo "Cleaning up external hbase tables"
hadoop fs -rm -r -f ${FILESYSTEM_PREFIX}${TEST_WAREHOUSE_DIR}/functional_hbase.db

echo "Cleaning up workspace"
rm -rf ${SNAPSHOT_STAGING_DIR}
