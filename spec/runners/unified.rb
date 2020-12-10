require 'runners/unified/entity_map'
require 'runners/unified/event_subscriber'
require 'runners/unified/test'
require 'runners/unified/test_group'
require 'runners/unified/using_hash'

def define_unified_spec_tests(base_path, paths)
  paths.each do |path|
    context path[base_path.length+1...path.length] do
      group = Unified::TestGroup.new(path)

      group.tests.each do |test|
        context test.description do

          if test.skip?
            before do
              skip test.skip_reason
            end
          end

          before(:all) do
            if ClusterConfig.instance.topology == :sharded
              if test.require_multiple_mongoses? && SpecConfig.instance.addresses.length == 1
                skip "Test requires multiple mongoses"
              elsif test.require_single_mongos? && SpecConfig.instance.addresses.length > 1
                # Many transaction spec tests that do not specifically deal with
                # sharded transactions fail when run against a multi-mongos cluster
                skip "Test requires single mongos"
              end
            end
          end

          it 'passes' do
            if test.group_reqs
              unless test.group_reqs.any? { |r| r.satisfied? }
                skip "Group requirements not satisfied"
              end
            end
            if test.reqs
              unless test.reqs.any? { |r| r.satisfied? }
                skip "Requirements not satisfied"
              end
            end
            test.create_entities
            test.set_initial_data
            test.run
            test.assert_outcome
            test.assert_events
            test.cleanup
          end
        end
      end
    end
  end
end