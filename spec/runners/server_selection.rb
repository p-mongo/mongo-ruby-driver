module Mongo
  module ServerSelection
    module Read

      # Represents a Server Selection specification test.
      #
      # @since 2.0.0
      class Spec

        # Mapping of read preference modes.
        #
        # @since 2.0.0
        READ_PREFERENCES = {
          'Primary' => :primary,
          'Secondary' => :secondary,
          'PrimaryPreferred' => :primary_preferred,
          'SecondaryPreferred' => :secondary_preferred,
          'Nearest' => :nearest,
        }

        # @return [ String ] description The spec description.
        #
        # @since 2.0.0
        attr_reader :description

        # @return [ Hash ] read_preference The read preference to be used for selection.
        #
        # @since 2.0.0
        attr_reader :read_preference

        # @return [ Integer ] heartbeat_frequency The heartbeat frequency to be set on the client.
        #
        # @since 2.4.0
        attr_reader :heartbeat_frequency

        # @return [ Integer ] max_staleness The max_staleness.
        #
        # @since 2.4.0
        attr_reader :max_staleness

        # @return [ Mongo::Cluster::Topology ] type The topology type.
        #
        # @since 2.0.0
        attr_reader :type

        # Instantiate the new spec.
        #
        # @param [ String ] test_path The path to the file.
        #
        # @since 2.0.0
        def initialize(test_path)
          @test = BSON::ExtJSON.parse_obj(YAML.load(File.read(test_path)))
          @description = "#{@test['topology_description']['type']}: #{File.basename(test_path)}"
          @heartbeat_frequency = @test['heartbeatFrequencyMS'] / 1000 if @test['heartbeatFrequencyMS']
          @read_preference = @test['read_preference']
          @read_preference['mode'] = READ_PREFERENCES[@read_preference['mode']]
          @max_staleness = @read_preference['maxStalenessSeconds']
          @candidate_servers = @test['topology_description']['servers']
          @suitable_descriptions = @test['suitable_servers']
          if @test['in_latency_window']
            unless @test['in_latency_window'].is_a?(Array) && @test['in_latency_window'].length <= 1
              raise NotImplementedError, 'Runner only supports zero or one servers in latency window'
            end
            @description_in_latency_window = @test['in_latency_window'].first
          end
          @type = Mongo::Cluster::Topology.const_get(@test['topology_description']['type'])
        end

        # Whether this spec describes a replica set.
        #
        # @example Determine if the spec describes a replica set.
        #   spec.replica_set?
        #
        # @return [true, false] If the spec describes a replica set.
        #
        # @since 2.0.0
        def replica_set?
          type == Mongo::Cluster::Topology::ReplicaSetNoPrimary ||
          type == Mongo::Cluster::Topology::ReplicaSetWithPrimary
        end

        # Does this spec expect a server to be found.
        #
        # @example Will a server be found with this spec.
        #   spec.server_available?
        #
        # @return [true, false] If a server will be found with this spec.
        #
        # @since 2.0.0
        def server_available?
          !!description_in_latency_window
        end

        # Whether the test requires an error to be raised during server selection.
        #
        # @return [ true, false ] Whether the test expects an error.
        def error?
          !!@test['error']
        end

        # The subset of suitable servers that falls within the allowable latency
        #   window.
        #
        # @return [ Array<Hash> ] The servers within the latency window.
        #
        # @since 2.0.0
        attr_reader :description_in_latency_window

        attr_reader :suitable_descriptions

        # The servers a topology would return as candidates for selection.
        #
        # @return [ Array<Hash> ] candidate_servers The candidate servers.
        #
        # @since 2.0.0
        def candidate_servers
          @candidate_servers.select { |s| !['Unknown', 'PossiblePrimary'].include?(s['type']) }
        end

        private

        def primary
          @candidate_servers.find { |s| s['type'] == 'RSPrimary' }
        end
      end
    end
  end
end
