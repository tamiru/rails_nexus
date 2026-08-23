# frozen_string_literal: true

class CreateRailsNexusLoggedExceptions < ActiveRecord::Migration<%= "[#{ActiveRecord::Migration.current_version}]" %>
  def change
    create_table :rails_nexus_exceptions do |t|
      t.string :exception_class
      t.string :controller_name
      t.string :action_name
      t.text   :message
      t.text   :backtrace
      t.text   :environment
      t.text   :request
      t.string :user_info
      t.string :user_agent
      t.string :remote_ip

      t.timestamps
    end

    add_index :rails_nexus_exceptions, :created_at
    add_index :rails_nexus_exceptions, :exception_class
    add_index :rails_nexus_exceptions, [:controller_name, :action_name]
  end
end
