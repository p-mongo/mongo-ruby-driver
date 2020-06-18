require 'spec_helper'

require 'runners/server_selection'

describe 'Max Staleness Spec' do

  include Mongo::ServerSelection::Read

  MAX_STALENESS_TESTS.each do |file|

    spec = Mongo::ServerSelection::Read::Spec.new(file)

    context(spec.description) do
      # Cluster needs a topology and topology needs a cluster...
      # This temporary cluster is used for topology construction.
      let(:temp_cluster) do
        double('temp cluster').tap do |cluster|
          allow(cluster).to receive(:servers_list).and_return([])
        end
      end

      let(:topology) do
        options = if spec.type <= Mongo::Cluster::Topology::ReplicaSetNoPrimary
          {replica_set_name: 'foo'}
        else
          {}
        end
        spec.type.new(options, monitoring, temp_cluster)
      end

      let(:monitoring) do
        Mongo::Monitoring.new(monitoring: false)
      end

      let(:listeners) do
        Mongo::Event::Listeners.new
      end

      let(:options) do
        if spec.heartbeat_frequency
          SpecConfig.instance.test_options.merge(heartbeat_frequency: spec.heartbeat_frequency)
        else
          SpecConfig.instance.test_options.dup.tap do |opts|
            opts.delete(:heartbeat_frequency)
          end
        end.merge!(server_selection_timeout: 0.2, connect_timeout: 0.1)
      end

      let(:cluster) do
        double('cluster').tap do |c|
          allow(c).to receive(:connected?).and_return(true)
          allow(c).to receive(:summary)
          allow(c).to receive(:topology).and_return(topology)
          allow(c).to receive(:single?).and_return(topology.single?)
          allow(c).to receive(:sharded?).and_return(topology.sharded?)
          allow(c).to receive(:replica_set?).and_return(topology.replica_set?)
          allow(c).to receive(:unknown?).and_return(topology.unknown?)
          allow(c).to receive(:options).and_return(options)
          allow(c).to receive(:scan!).and_return(true)
          allow(c).to receive(:app_metadata).and_return(app_metadata)
          allow(c).to receive(:heartbeat_interval).and_return(
            spec.heartbeat_frequency || Mongo::Server::Monitor::DEFAULT_HEARTBEAT_INTERVAL)
        end
      end

      let(:candidate_servers) do
        spec.candidate_servers.collect do |server|
          features = double('features').tap do |feat|
            allow(feat).to receive(:max_staleness_enabled?).and_return(server['maxWireVersion'] && server['maxWireVersion'] >= 5)
            allow(feat).to receive(:check_driver_support!).and_return(true)
          end
          address = Mongo::Address.new(server['address'])
          Mongo::Server.new(address, cluster, monitoring, listeners,
            {monitoring_io: false}.update(options)
          ).tap do |s|
            allow(s).to receive(:average_round_trip_time).and_return(server['avg_rtt_ms'] / 1000.0) if server['avg_rtt_ms']
            allow(s).to receive(:tags).and_return(server['tags'])
            allow(s).to receive(:secondary?).and_return(server['type'] == 'RSSecondary')
            allow(s).to receive(:primary?).and_return(server['type'] == 'RSPrimary')
            allow(s).to receive(:connectable?).and_return(true)
            allow(s).to receive(:last_write_date).and_return(
              Time.at(server['lastWrite']['lastWriteDate'].to_f / 1000)) if server['lastWrite']
            allow(s).to receive(:last_scan).and_return(
              Time.at(server['lastUpdateTime'].to_f / 1000))
            allow(s).to receive(:features).and_return(features)
          end
        end
      end

      let(:server_in_latency_window) do
        description = spec.description_in_latency_window
        Mongo::Server.new(Mongo::Address.new(description['address']), cluster, monitoring, listeners,
          options.merge(monitoring_io: false))
      end

      let(:suitable_servers) do
        spec.suitable_servers.collect do |server|
          Mongo::Server.new(Mongo::Address.new(server['address']), cluster, monitoring, listeners,
            options.merge(monitoring_io: false))
        end
      end

      let(:server_selector_definition) do
        { mode: spec.read_preference['mode'] }.tap do |definition|
          definition[:tag_sets] = spec.read_preference['tag_sets']
          definition[:max_staleness] = spec.max_staleness if spec.max_staleness
        end
      end

      let(:server_selector) do
        Mongo::ServerSelector.get(server_selector_definition)
      end

      before do
        allow(cluster).to receive(:servers).and_return(candidate_servers)
        allow(cluster).to receive(:addresses).and_return(candidate_servers.map(&:address))
      end

      if spec.error?

        it 'Raises an InvalidServerPreference exception' do

          expect do
            server_selector.select_server(cluster)
          end.to raise_exception(Mongo::Error::InvalidServerPreference)
        end

      else

        if spec.server_available?

          it 'has non-empty suitable servers' do
            spec.suitable_descriptions.should be_a(Array)
            spec.suitable_descriptions.should_not be_empty
          end

          it 'has exactly one server in latency window' do
            # The spec readme stipulates that there is exactly one server
            server_in_latency_window.should_not be nil
          end

          it 'finds the correct server' do
            server_selector.select_server(cluster).should == server_in_latency_window
          end

          it 'identifies all suitable servers' do
            #expect(server_selector.send(:select, cluster.servers)).to match_array(suitable_servers)
          end

        else

          # Runner does not handle non-empty suitable servers with
          # no servers in latency window.
          it 'has empty suitable servers' do
            expect(spec.suitable_descriptions).to eq([])
          end

          it 'Raises a NoServerAvailable Exception' do
            expect do
              server_selector.select_server(cluster)
            end.to raise_exception(Mongo::Error::NoServerAvailable)
          end

        end
      end
    end
  end
end
