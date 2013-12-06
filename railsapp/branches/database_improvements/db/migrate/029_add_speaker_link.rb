class AddSpeakerLink < ActiveRecord::Migration
  def self.up
    add_column "talks", "speaker_url", :string
  end

  def self.down
    remove_column "talks", "speaker_url"
  end
end
