module Mongo
  module Transactions
    Context = Struct.new(
      :session0,
      :session1,
      :session,
    ) do
      def transform_arguments(arguments)
        arguments.dup.tap do |out|
          [:session].each do |key|
            if out[key]
              out[key] = send(key)
            end
          end
        end
      end
    end
  end
end

