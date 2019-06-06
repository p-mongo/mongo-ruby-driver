#!/bin/bash

set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

# Supported/used environment variables:
#       AUTH                    Set to enable authentication. Values are: "auth" / "noauth" (default)
#       SSL                     Set to enable SSL. Values are "ssl" / "nossl" (default)
#       MONGODB_URI             Set the suggested connection MONGODB_URI (including credentials and topology info)
#       TOPOLOGY                Allows you to modify variables and the MONGODB_URI based on test topology
#                               Supported values: "server", "replica_set", "sharded_cluster"
#       RVM_RUBY                Define the Ruby version to test with, using its RVM identifier.
#                               For example: "ruby-2.3" or "jruby-9.1"
#       DRIVER_TOOLS            Path to driver tools.

. `dirname "$0"`/functions.sh

arch=ubuntu1404
case $MONGODB_VERSION in
  2.6)
    version=2.6.12 ;;
  3.0)
    version=3.0.15 ;;
  3.2)
    version=3.2.22 ;;
  3.4)
    version=3.4.20 ;;
  3.6)
    # latest is 3.6.13
    version=3.6.12 ;;
  4.0)
    version=4.0.9 ;;
  latest)
    # latest is 4.1.13, this is ruby-1827
    version=4.1.9 ;;
  *)
    echo "Unknown version $MONGODB_VERSION" 1>&2
    exit 1
    ;;
esac
prepare_server $arch $version

install_mlaunch

# Launching mongod under $MONGO_ORCHESTRATION_HOME
# makes its long available through log collecting machinery

export dbdir="$MONGO_ORCHESTRATION_HOME"/db
mkdir -p "$dbdir"

args=''
options=''

if test "$SSL" = ssl; then
args="$args"\
"--sslMode requireSSL "\
"--sslPEMKeyFile spec/support/certificates/server.pem "\
"--sslCAFile spec/support/certificates/ca.crt "\
"--sslClientCertificate spec/support/certificates/client.pem"
options="$options"\
"&tls=true"\
"&tlsCAFile=spec/support/certificates/ca.crt"\
"&tlsCertificateKeyFile=spec/support/certificates/client.pem"
fi

case "$TOPOLOGY" in
  server)
    args="$args --single"
    hosts=localhost:27017
    ;;
  replica_set)
    args="$args --replicaset --name ruby-driver-rs"
    hosts=localhost:27017,localhost:27018,localhost:27019
    ;;
  sharded_cluster)
    args="$args --replicaset --sharded 2 --name ruby-driver-rs"
    hosts=localhost:27017
    ;;
  *)
    echo "Unknown topology $TOPOLOGY" 1>&2
    exit 1
    ;;
esac

auth_options=
if test "$AUTH" = auth; then
  args="$args --auth --username alice --password wland"
  auth_options="alice:wland@"
fi

mongod --version

mlaunch --dir "$dbdir" \
  --setParameter enableTestCommands=1 \
  --filePermissions 0666 \
  $args

export MONGODB_URI="mongodb://$auth_options$hosts/?serverSelectionTimeoutMS=30000$options"

set_fcv
set_env_vars

#export DRIVER_TOOLS_CLIENT_CERT_PEM="${DRIVERS_TOOLS}/.evergreen/x509gen/client-public.pem"
#export DRIVER_TOOLS_CLIENT_KEY_PEM="${DRIVERS_TOOLS}/.evergreen/x509gen/client-private.pem"
#export DRIVER_TOOLS_CLIENT_CERT_KEY_PEM="${DRIVERS_TOOLS}/.evergreen/x509gen/client.pem"
#export DRIVER_TOOLS_CA_PEM="${DRIVERS_TOOLS}/.evergreen/x509gen/ca.pem"
#export DRIVER_TOOLS_CLIENT_KEY_ENCRYPTED_PEM="${DRIVERS_TOOLS}/.evergreen/x509gen/password_protected.pem"

setup_ruby

install_deps

bundle exec rake spec:prepare

export MONGODB_URI="mongodb://$auth_options$hosts/?appName=CI$options"
echo "Running specs"
bundle exec rake spec:ci
test_status=$?
echo "TEST STATUS"
echo ${test_status}

kill_jruby

exit ${test_status}
