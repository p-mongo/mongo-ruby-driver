require 'spec_helper'
require 'timeout_interrupt'

describe Mongo::Collection::View::ChangeStream do
  before do
    unless test_change_streams?
      skip 'Not testing change streams'
    end
  end

  it 'returns data' do
  p authorized_client.database
  p authorized_collection.database
  #x
    cs = authorized_client.database.watch

    authorized_collection.insert_one(:a => 1)

    # stdlib timeout is not working here
    TimeoutInterrupt.timeout(1) do
      change = cs.to_enum.next
      expect(change['operationType']).to eql('insert')
      doc = change['fullDocument']
      expect(doc['_id']).to be_a(BSON::ObjectId)
      doc.delete('_id')
      expect(doc).to eql('a' => 1)
    end
  end
end
