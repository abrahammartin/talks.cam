namespace 'talks' do
  require File.dirname(__FILE__) + '/../../config/environment'

  class ConvertingUser < User
#    before_save :failfordebugpurposes
#    def failfordebugpurposes
#      return false
#    end

    def update_hash_from_legacy
      # This method reads directly from the underlying legacy column
      # and has access to the private set_password method
      legacy_password = read_attribute(:password)
      if legacy_password && !legacy_password.empty?
        set_password(read_attribute(:password))
      else
        puts "WARNING: Randomizing password for id=#{self.id} due to previous empty or nil password"
        randomize_password
      end
    end

    def update_crsid_from_email
      return true
    end

    def update_name_in_sort_order
      return true
    end

    # Stop updated_at column being changed by Rails
    self.record_timestamps = false

  end

  # USAGE:
  # rake 'talks:convert_users[dryrun]' RAILS_ENV=production 
  # OR
  # rake talks:convert_users RAILS_ENV=production

  task :convert_users, :runmode do |t, args|
    args.with_defaults(:runmode => "real")
    # e.g. set :runmode to 'dryrun'

    puts "Running with runmode = #{args.runmode}"

    schema_version = ActiveRecord::Migrator.current_version

    # Must be at exactly version 30 so that both columns are present
    raise "Wrong schema version" unless schema_version==30


    puts "Loading users..."
    users = ConvertingUser.find(:all)

    STDOUT.sync= true
    puts "Converting users..."

    users.each_with_index do |u, i|

      if (i % 50) == 0
        print "#{i} .. "
      end
  
      u.update_hash_from_legacy
  
      if args.runmode == "real"
        unless u.save
          puts "error saving user #{u.email} (id=#{u.id.to_s})"
        end
      end
  
    end

    puts users.length
    puts "Complete."

  end # end task

end
