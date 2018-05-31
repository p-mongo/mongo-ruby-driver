# Copyright (C) 2018 MongoDB Inc.
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

require 'securerandom'
require 'base64'
require 'mongo/auth/scram/conversation'

module Mongo
  module Auth
    class SCRAM256

      # Defines behaviour around a single SCRAM-SHA-256 conversation between the
      # client and server.
      #
      # @since 2.6.0
      class Conversation < SCRAM::Conversation

        # The authentication mechanism string.
        #
        # @since 2.6.0
        MECHANISM = 'SCRAM-SHA-256'.freeze

        # The digest to use for encryption.
        #
        # @since 2.6.0
        DIGEST = OpenSSL::Digest::SHA256

        # The minimum iteration count for the authentication mechanism.
        #
        # @since 2.6.0
        MIN_ITER_COUNT = 4096

        private

        # HI algorithm implementation.
        #
        # @api private
        #
        # @see http://tools.ietf.org/html/rfc5802#section-2.2
        #
        # @since 2.6.0
        def hi(data)
          OpenSSL::PKCS5.pbkdf2_hmac(
            data,
            Base64.strict_decode64(salt),
            iterations,
            digest.size,
            DIGEST
          )
        end

        # Get the iterations from the server response.
        #
        # @api private
        #
        # @since 2.6.0
        def iterations
          @iterations ||= payload_data.match(ITERATIONS)[1].to_i.tap do |i|
            next unless i < MIN_ITER_COUNT
            raise Error::InsufficientIterationCount.new(
                Error::InsufficientIterationCount.message(MIN_ITER_COUNT, i))
          end
        end

        # Salted password algorithm implementation.
        #
        # @api private
        #
        # @see http://tools.ietf.org/html/rfc5802#section-3
        #
        # @since 2.6.0
        def salted_password
          @salted_password ||= hi(user.sasl_prepped_hashed_password)
        end
      end
    end
  end
end
