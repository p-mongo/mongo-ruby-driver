require 'spec_helper'

describe 'fork reconnect' do
  only_mri

  before(:all) do
    if !SpecConfig.instance.stress_spec?
      skip 'Stress spec not enabled'
    end
  end

  let(:client) { authorized_client }

  describe 'client' do
    it 'works after fork' do
      client.database.command(ismaster: 1).should be_a(Mongo::Operation::Result)

      pids = []
      deadline = Time.now + 5
      1.upto(10) do
        if pid = fork
          pids << pid
        else
          while Time.now < deadline
            client.database.command(ismaster: 1).should be_a(Mongo::Operation::Result)
          end

          # Exec so that we do not close any clients etc. in the child.
          exec('/bin/true')
        end
      end

      while Time.now < deadline
        # Use a read which is retried in case of an error
        client['foo'].find(test: 1).to_a
      end

      pids.each do |pid|
        Process.wait(pid)
        $?.exitstatus.should == 0
      end
    end

    context 'when parent is operating on client during the fork' do
      # This test intermittently fails in evergreen with pool size of 5,
      # with a number o fpending connections in the pool.
      # The reason could be that handshaking is slow or operations are slow
      # post handshakes.
      let(:client) { authorized_client.with(max_pool_size: 10,
        wait_queue_timeout: 10, socket_timeout: 2, connect_timeout: 2) }

      it 'works' do
        client.database.command(ismaster: 1).should be_a(Mongo::Operation::Result)

        threads = []
        5.times do
          threads << Thread.new do
            loop do
              client['foo'].find(test: 1).to_a
            end
          end
        end

        pids = []
        deadline = Time.now + 5
        10.times do
          if pid = fork
            pids << pid
          else
            while Time.now < deadline
              client.database.command(ismaster: 1).should be_a(Mongo::Operation::Result)
            end

            # Exec so that we do not close any clients etc. in the child.
            exec('/bin/true')
          end
        end

        while Time.now < deadline
          sleep 0.1
        end

        threads.map(&:kill)
        threads.map(&:join)

        pids.each do |pid|
          Process.wait(pid)
          $?.exitstatus.should == 0
        end
      end

    end
  end
end