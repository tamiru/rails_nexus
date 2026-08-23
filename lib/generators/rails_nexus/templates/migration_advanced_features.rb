class AddAdvancedFeaturesToRailsNexusLoggedExceptions < ActiveRecord::Migration[8.0]
  def change
    # Exception cause chain
    add_column :rails_nexus_exceptions, :cause_chain, :text

    # Breadcrumbs (activity trail before crash)
    add_column :rails_nexus_exceptions, :breadcrumbs, :text

    # System health snapshot at crash time
    add_column :rails_nexus_exceptions, :system_health, :text

    # User impact tracking
    add_column :rails_nexus_exceptions, :user_id, :string
    add_column :rails_nexus_exceptions, :user_type, :string

    # Storm protection: occurrence count (deduplication)
    add_column :rails_nexus_exceptions, :occurrence_count, :integer, default: 1

    # Custom fingerprint for grouping
    add_column :rails_nexus_exceptions, :fingerprint, :string

    # Local/instance variables captured at raise time
    add_column :rails_nexus_exceptions, :local_variables, :text
    add_column :rails_nexus_exceptions, :instance_variables, :text

    add_index :rails_nexus_exceptions, :user_id
    add_index :rails_nexus_exceptions, :fingerprint
    add_index :rails_nexus_exceptions, :occurrence_count
  end
end
