require 'spec_helper'

describe 'Server monitor' do
  describe 'heartbeats' do
    # For simplicity, test heartbeats in a single topology so that there is
    # exactly one server that is being monitored.
    require_topology :single

    before do
      ClientRegistry.instance.close_all_clients
    end

    it 'respects configured heartbeat frequency' do
      client = ClientRegistry.instance.global_client('authorized').with(
        app_name: 'server monitor integration', heartbeat_frequency: 1)
      subscriber = EventSubscriber.new
      client.subscribe(Mongo::Monitoring::SERVER_HEARTBEAT, subscriber)

      # 1.5 seconds should be enough time for the heartbeat to complete
      # but not enough time for the second one to start.
      sleep(1.5)

      expect(subscriber.started_events.length).to eq(1)
    end
  end
end
