require 'spec_helper'
#require 'timeout_interrupt'

describe Mongo::Collection::View::ChangeStream do
  before do
    unless test_change_streams?
      skip 'Not testing change streams'
    end
  end

  let(:client) { Mongo::Client.new(authorized_client.cluster.addresses.map(&:to_s), database: 'test') }
  let(:database) { client }
  let(:collection) { client['change-stream-integration'] }

  it 'returns data' do
  p client.database
    cs = client.database.watch

    collection.insert_one(:a => 1)

    # stdlib timeout is not working here
    #TimeoutInterrupt.timeout(1) do
    #byebug
      change = cs.to_enum.try_next
      expect(change).to be_a(BSON::Document)
      expect(change['operationType']).to eql('insert')
      doc = change['fullDocument']
      expect(doc['_id']).to be_a(BSON::ObjectId)
      doc.delete('_id')
      expect(doc).to eql('a' => 1)
    #end
  end
end
