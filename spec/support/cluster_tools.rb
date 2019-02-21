require 'singleton'

class ClusterTools
  include Singleton

  def step_down
    admin_client.database.command(replSetStepDown: nil)
  end

  def change_primary
    primary = admin_client.cluster.next_primary
    step_down
    sleep 1
    primary.unknown!
    new_primary = admin_client.cluster.next_primary
    if primary.address == new_primary.address
      raise "Failed to change primary"
    end
  end

  private

  def admin_client
    # Since we are triggering elections, we need to have a higher server
    # selection timeout applied. The default timeout for tests assumes a
    # stable deployment.
    @admin_client ||= ClientRegistry.instance.global_client('root_authorized_admin').
      with(server_selection_timeout: 15)
  end
end
