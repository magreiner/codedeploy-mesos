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

# set environment variables for all users
echo JAVA_HOME=/usr/java/default >> /etc/environment
echo "SPARK_HOME=/opt/spark" >> /etc/environment
echo "export JAVA_HOME=/usr/java/default" >> /etc/bash.bashrc
echo "export PATH=\$PATH:/opt/spark/bin" >> /etc/bash.bashrc

# Export variables
export JAVA_HOME=/usr/java/default
export SPARK_HOME=/opt/spark

# only re-download spark if its not already running
# if its there but not running cleanup and replace it with newer version
# if [ "1" -ge "$(ps -aux | grep spark.deploy.worker | wc -l)" ]; then
  # rm -rf "$SPARK_HOME" &>/dev/null
if [ ! -d "$SPARK_HOME" ]; then
  # install aws requierements
  pip install awscli

  mkdir -p "$SPARK_HOME"
  /usr/local/bin/aws s3 cp --region $AWS_REGION "s3://$S3_BUCKET/clusterData/spark-$SPARK_VERSION-bin-hadoop2.6.tgz" - |\
    tar -C "$SPARK_HOME"  --strip-components=1 -zxf -
fi
export PATH=$JAVA_HOME/bin:$PATH

MASTER_INSTANCE_TAGNAME="AS_Master"

AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
REGION="${AZ::-1}"
MASTER_IPS="$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=$MASTER_INSTANCE_TAGNAME" --query 'Reservations[*].Instances[*].NetworkInterfaces[*].PrivateIpAddress' --output text)"
FIRST_MASTER_IP="$(echo "$MASTER_IPS" | head -n1)"
LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > "$SPARK_HOME/conf/log4j.properties" << EOF
# Set everything to be logged to the console
log4j.rootCategory=WARN, console
log4j.appender.console=org.apache.log4j.ConsoleAppender
log4j.appender.console.target=System.err
log4j.appender.console.layout=org.apache.log4j.PatternLayout
log4j.appender.console.layout.ConversionPattern=%d{yy/MM/dd HH:mm:ss} %p %c{1}: %m%n

# Settings to quiet third party logs that are too verbose
log4j.logger.org.spark-project.jetty=WARN
log4j.logger.org.spark-project.jetty.util.component.AbstractLifeCycle=ERROR
log4j.logger.org.apache.spark.repl.SparkIMain$exprTyper=WARN
log4j.logger.org.apache.spark.repl.SparkILoop$SparkILoopInterpreter=WARN
log4j.logger.org.apache.parquet=ERROR
log4j.logger.parquet=ERROR

# SPARK-9183: Settings to avoid annoying messages when looking up nonexistent UDFs in SparkSQL with Hive support
log4j.logger.org.apache.hadoop.hive.metastore.RetryingHMSHandler=FATAL
log4j.logger.org.apache.hadoop.hive.ql.exec.FunctionRegistry=ERROR
EOF

cat > "$SPARK_HOME/conf/spark-env.sh" << EOF
# Options read when launching programs locally with
# ./bin/run-example or ./bin/spark-submit
# - HADOOP_CONF_DIR, to point Spark towards Hadoop configuration files
# - SPARK_LOCAL_IP, to set the IP address Spark binds to on this node
SPARK_LOCAL_IP="$LOCAL_IP"
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
SPARK_MASTER_IP="$FIRST_MASTER_IP"
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

cat > "$SPARK_HOME/conf/spark-defaults.conf" << EOF
# Default system properties included when running spark-submit.
# This is useful for setting default environmental settings.

# Example:
# spark.master                     spark://master:7077
spark.master                       spark://$FIRST_MASTER_IP:7077
# spark.eventLog.enabled           true
# spark.eventLog.dir               hdfs://namenode:8021/directory
# spark.serializer                 org.apache.spark.serializer.KryoSerializer
# spark.driver.memory              5g
# spark.executor.extraJavaOptions  -XX:+PrintGCDetails -Dkey=value -Dnumbers="one two three"
spark.driver.cores          2
spark.driver.memory         2G
spark.driver.maxResultSize  5G
spark.executor.memory       5G
EOF

# get twitter credentials
aws s3 cp --region eu-central-1 s3://filestore-eu-central-1/clusterData/twitter4j.properties /opt/spark/conf/

# start spark
if [ "$NODE_TYPE" = "master" ]; then
  RUN_INFO=$($SPARK_HOME/sbin/start-master.sh)
else
  RUN_INFO=$($SPARK_HOME/sbin/start-slave.sh spark://$FIRST_MASTER_IP:7077)
fi
if [ "$MODE" != "quiet" ]; then
  LOGFILE=$(echo $RUN_INFO | grep $SPARK_HOME | cut -d' ' -f5)
  tail -F -n +1 $LOGFILE
fi
