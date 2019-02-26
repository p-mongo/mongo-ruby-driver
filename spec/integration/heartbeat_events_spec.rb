require 'spec_helper'

describe 'Heartbeat events' do
  class HeartbeatEventsSpecTestException < StandardError; end

  let(:subscriber) { EventSubscriber.new }

  before(:all) do
    ClientRegistry.instance.close_all_clients
  end

  before do
    Mongo::Monitoring::Global.subscribe(Mongo::Monitoring::SERVER_HEARTBEAT, subscriber)
  end

  after do
    Mongo::Monitoring::Global.unsubscribe(Mongo::Monitoring::SERVER_HEARTBEAT, subscriber)
  end

  let(:client) { new_local_client([SpecConfig.instance.addresses.first],
    authorized_client.options.merge(server_selection_timeout: 0.1, connect: :direct)) }

  it 'notifies on successful heartbeats' do
    client.database.command(ismaster: 1)

    started_event = subscriber.started_events.first
    expect(started_event).not_to be nil
    expect(started_event.address).to be_a(Mongo::Address)
    expect(started_event.address.seed).to eq(SpecConfig.instance.addresses.first)

    succeeded_event = subscriber.succeeded_events.first
    expect(succeeded_event).not_to be nil
    expect(succeeded_event.address).to be_a(Mongo::Address)
    expect(succeeded_event.address.seed).to eq(SpecConfig.instance.addresses.first)

    failed_event = subscriber.failed_events.first
    expect(failed_event).to be nil
  end

  it 'notifies on failed heartbeats' do
    exc = HeartbeatEventsSpecTestException.new
    expect_any_instance_of(Mongo::Server::Monitor::Connection).to receive(:ismaster).at_least(:once).and_raise(exc)

    expect do
      client.database.command(ismaster: 1)
    end.to raise_error(Mongo::Error::NoServerAvailable)

    started_event = subscriber.started_events.first
    expect(started_event).not_to be nil
    expect(started_event.address).to be_a(Mongo::Address)
    expect(started_event.address.seed).to eq(SpecConfig.instance.addresses.first)

    succeeded_event = subscriber.succeeded_events.first
    expect(succeeded_event).to be nil

    failed_event = subscriber.failed_events.first
    expect(failed_event).not_to be nil
    expect(failed_event.error).to be exc
    expect(failed_event.failure).to be exc
    expect(failed_event.address).to be_a(Mongo::Address)
    expect(failed_event.address.seed).to eq(SpecConfig.instance.addresses.first)
  end

  context 'when monitoring option is false' do
    let(:client) { new_local_client([SpecConfig.instance.addresses.first],
      authorized_client.options.merge(server_selection_timeout: 0.1, connect: :direct,
        monitoring: false)) }

    shared_examples_for 'does not notify on heartbeats' do
      it 'does not notify on heartbeats' do
        client.database.command(ismaster: 1)

        started_event = subscriber.started_events.first
        expect(started_event).to be nil
      end
    end

    it_behaves_like 'does not notify on heartbeats'

    context 'when a subscriber is added manually' do
      let(:client) do
        sdam_proc = Proc.new do |client|
          client.subscribe(Mongo::Monitoring::SERVER_HEARTBEAT, subscriber)
        end

        new_local_client([SpecConfig.instance.addresses.first],
          authorized_client.options.merge(server_selection_timeout: 0.1, connect: :direct,
            monitoring: false, sdam_proc: sdam_proc))
      end

      it_behaves_like 'does not notify on heartbeats'
    end
  end
end
