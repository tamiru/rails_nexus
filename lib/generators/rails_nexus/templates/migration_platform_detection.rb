class AddPlatformToRailsNexusLoggedExceptions < ActiveRecord::Migration[8.0]
  def change
    add_column :rails_nexus_exceptions, :platform, :string, default: "web"
    add_column :rails_nexus_exceptions, :platform_version, :string
    add_column :rails_nexus_exceptions, :device_type, :string
    add_column :rails_nexus_exceptions, :app_version, :string

    add_index :rails_nexus_exceptions, :platform
    add_index :rails_nexus_exceptions, [:platform, :exception_class]
  end
end
