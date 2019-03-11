# Copyright (C) 2014-2019 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mongo/server/connection_pool/queue'

module Mongo
  class Server

    # Represents a connection pool for server connections.
    #
    # @since 2.0.0
    class ConnectionPool
      include Id
      include Loggable
      include Monitoring::Publishable
      extend Forwardable

      # The default timeout, in seconds, to wait for a connection.
      DEFAULT_WAIT_TIMEOUT = 1.freeze

      # Create the new connection pool.
      #
      # @param [ Server ] server The server which this connection pool is for.
      # @param [ Hash ] options The connection pool options.
      #
      # @option options [ Address ] :address The address that this connection
      #   pool is for.
      # @option options [ Monitoring ] :monitoring The monitoring.
      # @option options [ Integer ] :max_pool_size The maximum pool size.
      # @option options [ Integer ] :min_pool_size The minimum pool size.
      # @option options [ Float ] :wait_queue_timeout The time to wait, in
      #   seconds, for a free connection.
      #
      # @since 2.0.0, API changed in 2.9.0
      def initialize(server, options = {})
        unless server.is_a?(Server)
          raise ArgumentError, 'First argument must be a Server instance'
        end
        @server = server
        @monitoring = server.monitoring
        if Lint.enabled? && @monitoring.nil?
          raise Error::LintError, 'Connection pool created without a monitoring object'
        end
        @options = options.dup.freeze
        @queue = queue = Queue.new(@options) do |generation|
          Connection.new(server, options.merge(generation: generation))
        end
        @closed = false

        finalizer = proc do
          queue.disconnect!(:pool_closed)
        end
        ObjectSpace.define_finalizer(self, finalizer)

        publish_cmap_event(
          Monitoring::Event::Cmap::PoolCreated.new(address, options)
        )
      end

      # @return [ String ] address The address the pool's connections will connect to.
      #
      # @since 2.8.0
      attr_reader :address

      # @return [ Hash ] options The pool options.
      attr_reader :options

      # The time to wait, in seconds, for a connection to become available
      # when a connection is being checked out and the pool is at its maximim
      # size.
      #
      # @example Get the wait timeout.
      #   queue.wait_timeout
      #
      # @return [ Float ] The wait timeout.
      #
      # @since 2.0.0
      def wait_timeout
        @wait_timeout ||= options[:wait_queue_timeout] || DEFAULT_WAIT_TIMEOUT
      end

      # Whether the pool has been closed.
      #
      # @return [ true | false ] Whether the pool is closed.
      #
      # @since 2.8.0
      def closed?
        @closed
      end

      def_delegators :queue, :close_stale_sockets!

      # Check a connection back into the pool. Will pull the connection from a
      # thread local stack that should contain it after it was checked out.
      #
      # @example Checkin the thread's connection to the pool.
      #   pool.checkin
      #
      # @since 2.0.0
      def checkin(connection)
        # The pool may be closed here.

        if closed?
          queue.close_checked_out_connection(connection, :pool_closed)
        else
          queue.enqueue(connection)
        end
      end

      # Check a connection out from the pool. If a connection exists on the same
      # thread it will get that connection, otherwise it will dequeue a
      # connection from the queue and pin it to this thread.
      #
      # @example Check a connection out from the pool.
      #   pool.checkout
      #
      # @return [ Mongo::Server::Connection ] The checked out connection.
      #
      # @since 2.0.0
      def checkout
        raise_if_closed!

        publish_cmap_event(
          Monitoring::Event::Cmap::ConnectionCheckoutStarted.new(address)
        )

        begin
          queue.dequeue.tap do |connection|
            # If connection fails, we are in trouble.
            connection.connect!

            publish_cmap_event(
              Monitoring::Event::Cmap::ConnectionCheckedOut.new(address, connection.id),
            )
          end
        rescue Timeout::Error
          publish_cmap_event(
            Monitoring::Event::Cmap::ConnectionCheckoutFailed.new(
              address,
              Monitoring::Event::Cmap::ConnectionCheckoutFailed::TIMEOUT,
            ),
          )
          raise
        end
      end

      # Closes all idle connections in the pool and schedules currently checked
      # out connections to be closed when they are checked back into the pool.
      # The pool remains operational and can create new connections when
      # requested.
      #
      # @return [ true ] true.
      #
      # @since 2.8.0
      def clear(reason = :stale)
        raise_if_closed!

        queue.disconnect!(reason)

        publish_cmap_event(
          Monitoring::Event::Cmap::PoolCleared.new(address)
        )

        true
      end

      # @since 2.1.0
      # @deprecated
      alias :disconnect! :clear

      # Marks the pool closed, closes all idle connections in the pool and
      # schedules currently checked out connections to be closed when they are
      # checked back into the pool. Attempts to use the pool after it is closed
      # will raise Error::PoolClosedError.
      #
      # @return [ true ] true.
      #
      # @since 2.8.0
      def close
        return if closed?

        queue.disconnect!(:pool_closed)

        publish_cmap_event(
          Monitoring::Event::Cmap::PoolClosed.new(address)
        )

        @closed = true
      end

      # Get a pretty printed string inspection for the pool.
      #
      # @example Inspect the pool.
      #   pool.inspect
      #
      # @return [ String ] The pool inspection.
      #
      # @since 2.0.0
      def inspect
        "#<Mongo::Server::ConnectionPool:0x#{object_id} queue=#{queue.inspect}>"
      end

      # Yield the block to a connection, while handling checkin/checkout logic.
      #
      # @example Execute with a connection.
      #   pool.with_connection do |connection|
      #     connection.read
      #   end
      #
      # @return [ Object ] The result of the block.
      #
      # @since 2.0.0
      def with_connection
        raise_if_closed!

        connection = checkout
        yield(connection)
      ensure
        checkin(connection) if connection
      end

      protected

      attr_reader :queue

      private

      # Asserts that the pool has not been closed.
      #
      # @raise [ Error::PoolClosed ] If the pool has been closed.
      #
      # @since 2.8.0
      def raise_if_closed!
        if closed?
          raise Error::PoolClosedError.new(address)
        end
      end
    end
  end
end
