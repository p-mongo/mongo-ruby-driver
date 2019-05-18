require 'spec_helper'

describe do
  define_crud_spec_tests('CRUD spec tests', CRUD_TESTS) do |spec, req, test|
    let(:client) { authorized_client }
  end
end
