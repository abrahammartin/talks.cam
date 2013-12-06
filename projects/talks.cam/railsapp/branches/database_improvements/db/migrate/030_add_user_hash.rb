class AddUserHash < ActiveRecord::Migration
  def self.up
    add_column "users", "password_hash", :string, :limit => 60
  end

  def self.down
    remove_column "users", "password_hash"
  end
end
