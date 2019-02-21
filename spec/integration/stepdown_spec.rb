require 'spec_helper'

describe 'Stepdown behavior' do
  min_server_fcv '4.2'

  describe 'getMore iteration' do
    let(:collection) { subscribed_client['stepdown'] }

    before do
      collection.insert_many([{test: 1}] * 100)
    end

    let(:view) { collection.find({test: 1}, batch_size: 10) }
    let(:enum) { view.to_enum }

    it 'continues through stepdown' do

      EventSubscriber.clear_events!

      # get the first item
      item = enum.next
      expect(item['test']).to eq(1)

      find_events = EventSubscriber.started_events.select do |event|
        event.command['find']
      end
      expect(find_events.length).to eq(1)
      find_socket_object_id = find_events.first.socket_object_id
      expect(find_socket_object_id).to be_a(Numeric)

      ClusterTools.instance.change_primary

      EventSubscriber.clear_events!

      # exhaust the batch
      9.times do
        enum.next
      end

      # this should issue a getMore
      item = enum.next
      expect(item['test']).to eq(1)

      get_more_events = EventSubscriber.started_events.select do |event|
        event.command['getMore']
      end

      expect(get_more_events.length).to eq(1)

      # getMore should have been sent on the same connection as find
      get_more_socket_object_id = get_more_events.first.socket_object_id
      expect(get_more_socket_object_id).to eq(find_socket_object_id)
    end
  end
end
