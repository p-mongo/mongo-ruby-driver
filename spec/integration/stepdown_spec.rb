require 'spec_helper'

describe 'Stepdown behavior' do
  min_server_fcv '4.2'

  describe 'getMore iteration' do
    let(:collection) { authorized_client['stepdown'] }

    before do
      collection.insert_many([{test: 1}] * 100)
    end

    let(:view) { collection.find({test: 1}, batch_size: 10) }
    let(:enum) { view.to_enum }

    it 'continues through stepdown' do
      # get the first item
      item = enum.next
      expect(item['test']).to eq(1)

      ClusterTools.instance.change_primary

      # exhaust the batch
      9.times do
        enum.next
      end

      # this should issue a getMore
      item = enum.next
      expect(item['test']).to eq(1)
    end
  end
end
