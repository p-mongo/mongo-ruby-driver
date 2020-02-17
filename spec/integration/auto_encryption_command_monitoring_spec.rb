require 'spec_helper'

describe 'Auto Encryption' do
  require_libmongocrypt
  require_enterprise
  min_server_fcv '4.2'

  # Diagnostics of leaked background threads only, these tests do not
  # actually require a clean slate. https://jira.mongodb.org/browse/RUBY-2138
  clean_slate

  include_context 'define shared FLE helpers'
  include_context 'with local kms_providers'

  let(:subscriber) { EventSubscriber.new }

  let(:encryption_client) do
    new_local_client(
      SpecConfig.instance.addresses,
      SpecConfig.instance.test_options.merge(
        auto_encryption_options: {
          kms_providers: kms_providers,
          key_vault_namespace: key_vault_namespace,
          schema_map: { "auto_encryption.users" => schema_map },
        },
        database: 'auto_encryption'
      ),
    ).tap do |client|
      client.subscribe(Mongo::Monitoring::COMMAND, subscriber)
    end
  end

  before(:each) do
    authorized_client.use(key_vault_db)[key_vault_coll].drop
    authorized_client.use(key_vault_db)[key_vault_coll].insert_one(data_key)

    encryption_client[:users].drop
    result = encryption_client[:users].insert_one(ssn: ssn, age: 23)
  end

  let(:started_event) do
    subscriber.started_events.find do |event|
      event.command_name == command_name
    end
  end

  let(:succeeded_event) do
    subscriber.succeeded_events.find do |event|
      event.command_name == command_name
    end
  end

  describe '#aggregate' do
    let(:command_name) { 'aggregate' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].aggregate([{ '$match' => { 'ssn' => ssn } }]).first

      # Command started event occurs after ssn is encrypted
      expect(
        started_event.command["pipeline"].first["$match"]["ssn"]["$eq"]
      ).to be_ciphertext

      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["cursor"]["firstBatch"].first["ssn"]).to be_ciphertext
    end
  end

  describe '#count' do
    let(:command_name) { 'count' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].count(ssn: ssn)

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["query"]["ssn"]["$eq"]).to be_ciphertext
    end
  end

  describe '#distinct' do
    let(:command_name) { 'distinct' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].distinct(:ssn)

      # Command started event does not contain any data to be encrypted
      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["values"].first).to be_ciphertext
    end
  end

  describe '#delete_one' do
    let(:command_name) { 'delete' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].delete_one(ssn: ssn)

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["deletes"].first["q"]["ssn"]["$eq"]).to be_ciphertext
    end
  end

  describe '#delete_many' do
    let(:command_name) { 'delete' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].delete_many(ssn: ssn)

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["deletes"].first["q"]["ssn"]["$eq"]).to be_ciphertext
    end
  end

  describe '#find' do
    let(:command_name) { 'find' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].find(ssn: ssn).first

      # Command started event occurs after ssn is encrypted
      expect(started_event.command["filter"]["ssn"]["$eq"]).to be_ciphertext

      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["cursor"]["firstBatch"].first["ssn"]).to be_ciphertext
    end
  end

  describe '#find_one_and_delete' do
    let(:command_name) { 'findAndModify' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].find_one_and_delete(ssn: ssn)

      # Command started event occurs after ssn is encrypted
      expect(started_event.command["query"]["ssn"]["$eq"]).to be_ciphertext

      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["value"]["ssn"]).to be_ciphertext
    end
  end

  describe '#find_one_and_replace' do
    let(:command_name) { 'findAndModify' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].find_one_and_replace(
        { ssn: ssn },
        { ssn: '555-555-5555' }
      )

      # Command started event occurs after ssn is encrypted
      expect(started_event.command["query"]["ssn"]["$eq"]).to be_ciphertext
      expect(started_event.command["update"]["ssn"]).to be_ciphertext

      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["value"]["ssn"]).to be_ciphertext
    end
  end

  describe '#find_one_and_update' do
    let(:command_name) { 'findAndModify' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].find_one_and_update(
        { ssn: ssn },
        { ssn: '555-555-5555' }
      )

      # Command started event occurs after ssn is encrypted
      expect(started_event.command["query"]["ssn"]["$eq"]).to be_ciphertext
      expect(started_event.command["update"]["ssn"]).to be_ciphertext

      # Command succeeded event occurs before ssn is decrypted
      expect(succeeded_event.reply["value"]["ssn"]).to be_ciphertext
    end
  end

  describe '#insert_one' do
    let(:command_name) { 'insert' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].insert_one(ssn: ssn)

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["documents"].first["ssn"]).to be_ciphertext
    end
  end

  describe '#replace_one' do
    let(:command_name) { 'update' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].replace_one(
        { ssn: ssn },
        { ssn: '555-555-5555' }
      )

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["updates"].first["q"]["ssn"]["$eq"]).to be_ciphertext
      expect(started_event.command["updates"].first["u"]["ssn"]).to be_ciphertext
    end
  end

  describe '#update_one' do
    let(:command_name) { 'update' }

    it 'has encrypted data in command monitoring' do
      encryption_client[:users].update_one({ ssn: ssn }, { ssn: '555-555-5555' })

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["updates"].first["q"]["ssn"]["$eq"]).to be_ciphertext
      expect(started_event.command["updates"].first["u"]["ssn"]).to be_ciphertext
    end
  end

  describe '#update_many' do
    let(:command_name) { 'update' }

    it 'has encrypted data in command monitoring' do
      # update_many does not support replacement-style updates
      encryption_client[:users].update_many({ ssn: ssn }, { "$inc" => { :age => 1 } })

      # Command started event occurs after ssn is encrypted
      # Command succeeded event does not contain any data to be decrypted
      expect(started_event.command["updates"].first["q"]["ssn"]["$eq"]).to be_ciphertext
    end
  end
end