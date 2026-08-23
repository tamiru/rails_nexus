# Migration for RailsNexus workflow management
# Adds priority, assignment, snooze, mute columns and comments table
class AddWorkflowToRailsNexus < ActiveRecord::Migration[8.0]
  def change
    # Workflow columns on logged_exceptions
    add_column :rails_nexus_exceptions, :priority, :string, default: nil
    add_column :rails_nexus_exceptions, :assigned_to, :string, default: nil
    add_column :rails_nexus_exceptions, :assigned_at, :datetime, default: nil
    add_column :rails_nexus_exceptions, :snoozed_until, :datetime, default: nil
    add_column :rails_nexus_exceptions, :muted, :boolean, default: false
    add_column :rails_nexus_exceptions, :muted_at, :datetime, default: nil
    add_column :rails_nexus_exceptions, :comments_count, :integer, default: 0

    add_index :rails_nexus_exceptions, :priority
    add_index :rails_nexus_exceptions, :assigned_to
    add_index :rails_nexus_exceptions, :muted

    # Comments table
    create_table :rails_nexus_comments do |t|
      t.references :logged_exception, null: false, foreign_key: { to_table: :rails_nexus_exceptions }
      t.string :author, null: false
      t.text :body, null: false
      t.string :comment_type, default: "comment" # comment, status_change, assignment, note
      t.timestamps
    end

    add_index :rails_nexus_comments, [:logged_exception_id, :created_at]
  end
end
