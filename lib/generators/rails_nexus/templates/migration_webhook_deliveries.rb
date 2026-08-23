class CreateRailsNexusWebhookDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_nexus_webhook_deliveries do |t|
      t.string :url, null: false
      t.string :status, null: false, default: "pending"
      t.integer :response_code
      t.text :request_body
      t.text :response_body
      t.float :duration
      t.text :error_message
      t.string :event_type
      t.json :metadata

      t.timestamps
    end

    add_index :rails_nexus_webhook_deliveries, :status
    add_index :rails_nexus_webhook_deliveries, :created_at
    add_index :rails_nexus_webhook_deliveries, :url
  end
end
