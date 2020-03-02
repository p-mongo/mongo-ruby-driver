require 'lite_spec_helper'

# Replica set name can be overridden via replicaSet parameter in MONGODB_URI
# environment variable or by specifying RS_NAME environment variable when
# not using MONGODB_URI.
TEST_SET = 'ruby-driver-rs'

require 'support/authorization'
require 'support/primary_socket'
require 'support/constraints'
require 'support/cluster_config'
require 'support/cluster_tools'
require 'rspec/retry'
require 'support/monitoring_ext'
require 'support/local_resource_registry'

RSpec.configure do |config|
  config.include(Authorization)
  config.extend(Constraints)

  config.before(:all) do
    if ClusterConfig.instance.fcv_ish >= '3.6'
      kill_all_server_sessions
    end
  end

  # RSpec seems to run all after hooks before returning to around hooks,
  # even if around hooks are defined later in program execution.
  # This means in order for local client cleanup to not interfere with
  # global assertions (guarded via scope_expectations), the cleanup has to
  # happen in an around hook also.
  config.around do |example|
    begin
      example.run
    ensure
      LocalResourceRegistry.instance.close_all
      ClientRegistry.instance.close_local_clients
    end
  end
end

# require all shared examples
Dir['./spec/support/shared/*.rb'].sort.each { |file| require file }
