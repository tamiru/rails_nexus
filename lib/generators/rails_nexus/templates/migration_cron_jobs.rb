class CreateRailsNexusCronJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_nexus_cron_jobs do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.text :output
      t.text :error_message
      t.float :duration
      t.string :hostname
      t.json :metadata
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :rails_nexus_cron_jobs, :name
    add_index :rails_nexus_cron_jobs, :status
    add_index :rails_nexus_cron_jobs, :created_at
    add_index :rails_nexus_cron_jobs, :started_at
  end
end
