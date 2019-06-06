set_fcv() {
  if test -n "$FCV"; then
    mongo --eval 'assert.commandWorked(db.adminCommand( { setFeatureCompatibilityVersion: "'"$FCV"'" } ));' "$MONGODB_URI"
    mongo --quiet --eval 'db.adminCommand( { getParameter: 1, featureCompatibilityVersion: 1 } )' "$MONGODB_URI" |grep  "version.*$FCV"
  fi
}

set_env_vars() {
  AUTH=${AUTH:-noauth}
  SSL=${SSL:-nossl}
  MONGODB_URI=${MONGODB_URI:-}
  TOPOLOGY=${TOPOLOGY:-server}
  DRIVERS_TOOLS=${DRIVERS_TOOLS:-}

  if [ "$AUTH" != "noauth" ]; then
    export ROOT_USER_NAME="bob"
    export ROOT_USER_PWD="pwd123"
  fi
  if [ "$COMPRESSOR" == "zlib" ]; then
    export COMPRESSOR="zlib"
  fi
  export CI=true
}

setup_ruby() {
  if test -z "$RVM_RUBY"; then
    echo "Empty RVM_RUBY, aborting"
    exit 2
  fi
  
  ls -l /opt

  # Necessary for jruby
  # Use toolchain java if it exists
  if [ -f /opt/java/jdk8/bin/java ]; then
    export JAVACMD=/opt/java/jdk8/bin/java
    export PATH=$PATH:/opt/java/jdk8/bin
  fi
    
  # ppc64le has it in a different place
  if test -z "$JAVACMD" && [ -f /usr/lib/jvm/java-1.8.0/bin/java ]; then
    export JAVACMD=/usr/lib/jvm/java-1.8.0/bin/java
    export PATH=$PATH:/usr/lib/jvm/java-1.8.0/bin
  fi

  if [ "$RVM_RUBY" == "ruby-head" ]; then
    # 12.04, 14.04 and 16.04 are good
    wget -O ruby-head.tar.bz2 http://rubies.travis-ci.org/ubuntu/`lsb_release -rs`/x86_64/ruby-head.tar.bz2
    tar xf ruby-head.tar.bz2
    export PATH=`pwd`/ruby-head/bin:`pwd`/ruby-head/lib/ruby/gems/2.6.0/bin:$PATH
    ruby --version
    ruby --version |grep dev
    
    #rvm reinstall $RVM_RUBY
  else
    if ! test "$RVM_RUBY" = ruby-1.9; then
    
    # For testing toolchains:
    toolchain_url=https://s3.amazonaws.com//mciuploads/mongo-ruby-toolchain/ubuntu1404/8cd47ac2cf636710740a6d79167f055e4c0a0154/mongo_ruby_driver_toolchain_ubuntu1404_patch_8cd47ac2cf636710740a6d79167f055e4c0a0154_5c452b76e3c3312273591db4_19_01_21_02_16_23.tar.gz
    curl -fL $toolchain_url |tar zxf -
    export PATH=`pwd`/rubies/$RVM_RUBY/bin:$PATH
    
    else
    
    # Normal operation
    if ! test -d $HOME/.rubies/$RVM_RUBY/bin; then
      echo "Ruby directory does not exist: $HOME/.rubies/$RVM_RUBY/bin" 1>&2
      echo "Contents of /opt:" 1>&2
      ls -l /opt 1>&2 || true
      echo ".rubies symlink:" 1>&2
      ls -ld $HOME/.rubies 1>&2 || true
      echo "Our rubies:" 1>&2
      ls -l $HOME/.rubies 1>&2 || true
      exit 2
    fi
    export PATH=$HOME/.rubies/$RVM_RUBY/bin:$PATH
    
    fi
    
    ruby --version

    # Ensure we're using the right ruby
    python - <<EOH
ruby = "${RVM_RUBY}".split("-")[0]
version = "${RVM_RUBY}".split("-")[1]
assert(ruby in "`ruby --version`")
assert(version in "`ruby --version`")
EOH

    # We shouldn't need to update rubygems, and there is value in
    # testing on whatever rubygems came with each supported ruby version
    #echo 'updating rubygems'
    #gem update --system

    # Only install bundler when not using ruby-head.
    # ruby-head comes with bundler and gem complains
    # because installing bundler would overwrite the bundler binary
    if test "$RVM_RUBY" = ruby-1.9 || test "$RVM_RUBY" = ruby-2.2 || echo "$RVM_RUBY" |grep -q jruby; then
      gem install bundler -v '<2'
    fi
  fi
}

install_deps() {
  echo "Installing all gem dependencies"
  bundle install
  bundle exec rake clean
}

kill_jruby() {
  jruby_running=`ps -ef | grep 'jruby' | grep -v grep | awk '{print $2}'`
  if [ -n "$jruby_running" ];then
    echo "terminating remaining jruby processes"
    for pid in $(ps -ef | grep "jruby" | grep -v grep | awk '{print $2}'); do kill -9 $pid; done
  fi
}

prepare_server() {
  arch=$1
  version=$2
  
  url=http://downloads.10gen.com/linux/mongodb-linux-x86_64-enterprise-$arch-$version.tgz
  mongodb_dir="$MONGO_ORCHESTRATION_HOME"/mdb
  mkdir -p "$mongodb_dir"
  curl $url |tar xz -C "$mongodb_dir" -f -
  BINDIR="$mongodb_dir"/`basename $url |sed -e s/.tgz//`/bin
  export PATH="$BINDIR":$PATH
}

install_mlaunch() {
  pythonpath="$MONGO_ORCHESTRATION_HOME"/python
  pip install -t "$pythonpath" 'mtools[mlaunch]'
  export PATH="$pythonpath/bin":$PATH
  export PYTHONPATH="$pythonpath"
}
