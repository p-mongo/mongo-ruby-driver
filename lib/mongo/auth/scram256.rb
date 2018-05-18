# Copyright (C) 2014 MongoDB Inc.
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

require 'mongo/auth/scram256/conversation'

module Mongo
  module Auth

    # Defines behaviour for SCRAM-SHA-256 authentication.
    #
    # @since 2.6.0
    class SCRAM256

      # The authentication mechanism string.
      #
      # @since 2.6.0
      MECHANISM = 'SCRAM-SHA-256'.freeze

      # @return [ Mongo::Auth::User ] The user to authenticate.
      attr_reader :user

      # Instantiate a new authenticator.
      #
      # @example Create the authenticator.
      #   Mongo::Auth::SCRAM256.new(user)
      #
      # @param [ Mongo::Auth::User ] user The user to authenticate.
      #
      # @since 2.6.0
      def initialize(user)
        @user = user
      end

      # Log the user in on the given connection.
      #
      # @example Log the user in.
      #   user.login(connection)
      #
      # @param [ Mongo::Connection ] connection The connection to log into.
      #   on.
      #
      # @return [ Protocol::Message ] The authentication response.
      #
      # @since 2.6.0
      def login(connection)
        conversation = Conversation.new(user)
        reply = connection.dispatch([ conversation.start(connection) ])
        connection.update_cluster_time(Operation::Result.new(reply))
        reply = connection.dispatch([ conversation.continue(reply, connection) ])
        connection.update_cluster_time(Operation::Result.new(reply))
        until reply.documents[0][Conversation::DONE]
          reply = connection.dispatch([ conversation.finalize(reply, connection) ])
          connection.update_cluster_time(Operation::Result.new(reply))
        end
        reply
      end
    end
  end
end
