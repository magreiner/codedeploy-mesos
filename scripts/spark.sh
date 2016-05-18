#!/bin/bash

# master or slave
NODE_TYPE="$1"

# quiet to prevent tail -f on log
MODE="$2"

export S3_BUCKET="filestore-eu-central-1"
export AWS_REGION="eu-central-1"
export SPARK_VERSION="1.6.1"
export SPARK_HOME="/opt/spark"

# Install requierements
DEBIAN_FRONTEND=noninteractive

apt-get install -qy python-software-properties software-properties-common
LC_ALL=C.UTF-8 add-apt-repository -y ppa:webupd8team/java
apt-get update
echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
apt-get install -qy curl \
                    python-pip \
                    oracle-java8-installer \
                    nano

mkdir -p /usr/java
rm -rf /usr/java/default &>/dev/null
ln -s /usr/lib/jvm/java-8-oracle/ /usr/java/default
echo JAVA_HOME=/usr/java/default >> /etc/environment
echo PATH=$JAVA_HOME/bin:$PATH >> /etc/environment

# Export variables
export JAVA_HOME=/usr/java/default

pip install awscli

# only re-download spark if its not already running
# if its there but not running cleanup and replace it with newer version
if [ "1" -ge "$(ps -aux | grep spark.deploy.worker | wc -l)" ]; then
  echo hi
fi
  rm -rf "$SPARK_HOME" &>/dev/null
  mkdir -p "$SPARK_HOME"
  /usr/local/bin/aws s3 cp --region $AWS_REGION "s3://$S3_BUCKET/clusterData/spark-$SPARK_VERSION-bin-hadoop2.6.tgz" - |\
    tar -C "$SPARK_HOME"  --strip-components=1 -zxf -
fi
export PATH=$JAVA_HOME/bin:$PATH

cat >> "$SPARK_HOME/conf/spark-env.sh" << EOF
# Options read when launching programs locally with
# ./bin/run-example or ./bin/spark-submit
# - HADOOP_CONF_DIR, to point Spark towards Hadoop configuration files
# - SPARK_LOCAL_IP, to set the IP address Spark binds to on this node
SPARK_LOCAL_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
# - SPARK_PUBLIC_DNS, to set the public dns name of the driver program
# - SPARK_CLASSPATH, default classpath entries to append

# Options read by executors and drivers running inside the cluster
# - SPARK_LOCAL_IP, to set the IP address Spark binds to on this node
# - SPARK_PUBLIC_DNS, to set the public DNS name of the driver program
# - SPARK_CLASSPATH, default classpath entries to append
# - SPARK_LOCAL_DIRS, storage directories to use on this node for shuffle and RDD data
# - MESOS_NATIVE_JAVA_LIBRARY, to point to your libmesos.so if you use Mesos

# Options read in YARN client mode
# - HADOOP_CONF_DIR, to point Spark towards Hadoop configuration files
# - SPARK_EXECUTOR_INSTANCES, Number of executors to start (Default: 2)
# - SPARK_EXECUTOR_CORES, Number of cores for the executors (Default: 1).
# - SPARK_EXECUTOR_MEMORY, Memory per Executor (e.g. 1000M, 2G) (Default: 1G)
# - SPARK_DRIVER_MEMORY, Memory for Driver (e.g. 1000M, 2G) (Default: 1G)
# - SPARK_YARN_APP_NAME, The name of your application (Default: Spark)
# - SPARK_YARN_QUEUE, The hadoop queue to use for allocation requests (Default: ‘default’)
# - SPARK_YARN_DIST_FILES, Comma separated list of files to be distributed with the job.
# - SPARK_YARN_DIST_ARCHIVES, Comma separated list of archives to be distributed with the job.

# Options for the daemons used in the standalone deploy mode
# - SPARK_MASTER_IP, to bind the master to a different IP address or hostname
SPARK_MASTER_IP="$SPARK_LOCAL_IP"
# - SPARK_MASTER_PORT / SPARK_MASTER_WEBUI_PORT, to use non-default ports for the master
SPARK_MASTER_WEBUI_PORT="8081"
# - SPARK_MASTER_OPTS, to set config properties only for the master (e.g. "-Dx=y")
# - SPARK_WORKER_CORES, to set the number of cores to use on this machine
# - SPARK_WORKER_MEMORY, to set how much total memory workers have to give executors (e.g. 1000m, 2g)
# - SPARK_WORKER_PORT / SPARK_WORKER_WEBUI_PORT, to use non-default ports for the worker
# - SPARK_WORKER_INSTANCES, to set the number of worker processes per node
# - SPARK_WORKER_DIR, to set the working directory of worker processes
# - SPARK_WORKER_OPTS, to set config properties only for the worker (e.g. "-Dx=y")
# - SPARK_DAEMON_MEMORY, to allocate to the master, worker and history server themselves (default: 1g).
# - SPARK_HISTORY_OPTS, to set config properties only for the history server (e.g. "-Dx=y")
# - SPARK_SHUFFLE_OPTS, to set config properties only for the external shuffle service (e.g. "-Dx=y")
# - SPARK_DAEMON_JAVA_OPTS, to set config properties for all daemons (e.g. "-Dx=y")
# - SPARK_PUBLIC_DNS, to set the public dns name of the master or workers

# Generic options for the daemons used in the standalone deploy mode
# - SPARK_CONF_DIR      Alternate conf dir. (Default: ${SPARK_HOME}/conf)
# - SPARK_LOG_DIR       Where log files are stored.  (Default: ${SPARK_HOME}/logs)
# - SPARK_PID_DIR       Where the pid file is stored. (Default: /tmp)
# - SPARK_IDENT_STRING  A string representing this instance of spark. (Default: $USER)
# - SPARK_NICENESS      The scheduling priority for daemons. (Default: 0)
EOF

if [ "$NODE_TYPE" = "master" ]; then
  RUN_INFO=$($SPARK_HOME/sbin/start-master.sh)
else
  MASTER_INSTANCE_TAGNAME="AS_Master"

  AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
  REGION="${AZ::-1}"
  MASTER_IPS="$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" --query 'Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddress' --output text)"
  FIRST_MASTER_IP="$(echo "$MASTER_IPS" | head -n1)"

  RUN_INFO=$($SPARK_HOME/sbin/start-slave.sh spark://$FIRST_MASTER_IP:7077)
fi
if [ "$MODE" != "quiet" ]; then
  LOGFILE=$(echo $RUN_INFO | grep $SPARK_HOME | cut -d' ' -f5)
  tail -F -n +1 $LOGFILE
fi
