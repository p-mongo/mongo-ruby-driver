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

  describe 'writes on connections' do
    let(:server) { authorized_client.with(app_name: rand).cluster.next_primary }
    let(:connection) { server.pool.checkout }
    let(:operation) do
      Mongo::Operation::Insert::OpMsg.new(
        documents: [{test: 1}],
        db_name: SpecConfig.instance.test_db,
        coll_name: 'stepdown',
        write_concern: Mongo::WriteConcern.get(write_concern),
      )
    end
    let(:message) { operation.send(:message, server) }
    let(:first_message) do
      Mongo::Operation::Insert::OpMsg.new(
        documents: [{test: 1}],
        db_name: SpecConfig.instance.test_db,
        coll_name: 'stepdown',
        write_concern: Mongo::WriteConcern.get(w: 1),
      ).send(:message, server)
    end

    after do
      server.pool.checkin(connection)
    end

    describe 'acknowledged write after stepdown' do
      let(:write_concern) { {:w => 1} }

      it 'keeps connection open' do
        rv = connection.dispatch([first_message], 1)
        expect(rv.documents.first['ok']).to eq(1)

        ClusterTools.instance.change_primary

        rv = connection.dispatch([message], 1)
        doc = rv.documents.first
        expect(doc['ok']).to eq(0)
        expect(doc['codeName']).to eq('NotMaster')

        expect(connection.connected?).to be true
      end
    end

    describe 'unacknowledged write after stepdown' do
      let(:write_concern) { {:w => 0} }

      it 'closes the connection' do
        rv = connection.dispatch([first_message], 1)
        p rv
        expect(rv.documents.first['ok']).to eq(1)

        ClusterTools.instance.change_primary

        connection.dispatch([message], 2)
        # No response will be returned hence we have no response assertions here

        expect(connection.connected?).to be false
      end
    end
  end
end
