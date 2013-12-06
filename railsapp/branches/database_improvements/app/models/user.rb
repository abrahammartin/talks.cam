require 'bcrypt'

class User < ActiveRecord::Base
  include BCrypt

  # This is used as an easier way of accessing who is the current user
  def User.current=(u)
    Thread.current[:user] = u
  end
  
  def User.current
    Thread.current[:user]
  end
  
  def User.search(search_term)
    return [] unless search_term && !search_term.empty?
    User.find_public(:all, :conditions => ["(name LIKE :search OR affiliation LIKE :search OR email LIKE :search)",{:search => "%#{search_term.strip}%"}], :order => 'name ASC' )
  end
  
  def User.find_public(*args)
    User.with_scope :find => { :conditions => ["ex_directory = 0"] } do
      User.find(*args)
    end
  end
  
  def User.sort_field; 'name_in_sort_order' end
  
  def User.find_or_create_by_crsid( crsid )
    user = User.find_by_crsid crsid
    return user if user
    # No email, so create
    User.create! :crsid => crsid, :email => "#{crsid}@cam.ac.uk", :affiliation => 'University of Cambridge'
  end
  
  # Lists that the user is mailed about
  has_many :email_subscriptions
  
  # Lists that this user manages
  has_many :list_users
  has_many :lists, :through => :list_users
  
  # Talks that this user speaks on
  has_many :talks, :foreign_key => 'speaker_id', :order => 'start_time DESC'
  
  # Talks that this user organises
  has_many :talks_organised, :class_name => "Talk", :foreign_key => 'organiser_id', :conditions => "ex_directory != 1", :order => 'start_time DESC'

  validates_uniqueness_of :email, :message => 'address is already registered on the system'
    
  # Life cycle actions
  before_save :update_crsid_from_email
  before_save :update_name_in_sort_order
  ## before_create :randomize_password ensures newly created users always have non-blank passwords.
  ## The plain-text of this first password is thrown away; Raven users should never need them.
  ## randomize_password will get called a second time if reset_and_send_password is called.
  before_create :randomize_password
  after_create :create_personal_list
  after_create :reset_and_send_password_if_required

  validate :validate_password_change_if_required
  
  # Try and prevent xss attacks
  include PreventScriptAttacks
  include CleanUtf # To try and prevent any malformed utf getting in
  
  # Has a connected image
  include BelongsToImage
  
  def editable?
    return false unless User.current
    ( User.current == self ) or ( User.current.administrator? )
  end
  
  def update_crsid_from_email
    return unless email =~ /^([a-z0-9]+)@cam.ac.uk$/i
    self.crsid = $1
  end
  
  def update_name_in_sort_order
    if name =~ /^\s*((.*) )?(.*)\s*$/
      self.name_in_sort_order = $2 ? "#{$3}, #{$2}" : $3
    else
      self.name_in_sort_order = ""
    end
  end
  
  def self.update_ex_directory_status
    User.find(:all).each { |u| u.update_ex_directory_status }
  end
  
  def update_ex_directory_status
    new_status = lists.find(:all,:conditions => ['ex_directory = 0']).empty? && talks.empty? && talks_organised.empty?
    update_attribute(:ex_directory,new_status) unless self.ex_directory? == new_status
    new_status
  end
  
  # Only accept new passwords when some confirmation is done
  # - user input:
  attr_accessor :password_confirmation
  attr_accessor :existing_password
  # - internal variables:
  attr_accessor :old_password
  attr_accessor :changing_password

  # NOTES:
  # The "password", "password=" and private "set_password" methods are all abstractions
  # over the actual "password_hash" string in the database.
  # password and old_password are actually in-memory BCrypt.Password objects, not strings

# TODO XXX need to update/add tests directory for these changes (not just this file, the whole branch)

  def password
    @password ||= Password.new(password_hash)
  end

  def is_password?(password_to_check)
    begin
      return password.is_password?(password_to_check)
    rescue StandardError => e
      logger.warn("WARNING: user.is_password? encountered an exception: #{e}")
      return false
    end
  end
  
  def password=(new_password)
    self.changing_password = true
    self.old_password = password
    set_password(new_password)
  end
  
  def validate_password_change_if_required
    min_password_length = 6
    if changing_password
      errors.add(:existing_password,"must match your existing password.") unless old_password.is_password?(existing_password)
      if !password.is_password?(password_confirmation)
        errors.add(:password_confirmation,"must match your new password.")
      else
        # We can't actually read back :password as a string so use password_confirmation once we know they match!!
        errors.add(:password,"must be at least #{min_password_length} characters long.") unless password_confirmation.length >= min_password_length
      end
    end
  end
  
  def randomize_password( size = 10 )
    chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
    newpassword = ""
    1.upto(size) { |i| newpassword << chars[rand(chars.size-1)] }
    set_password(newpassword)
    return newpassword
  end
  
  # After creating a user, create their personal list
  def create_personal_list
    list_name = 
      if self.name; "#{self.name}'s list"
      elsif self.crsid; "#{self.crsid}'s list"
      else; "Your personal list"
    end
    list = List.create! :name => list_name, :details => "A personal list of talks.", :ex_directory => true
    self.lists << list
  end
  
  # After creating a user, send them an e-mail with their password if this is set
  attr_accessor :send_email
  
  def reset_and_send_password_if_required
    reset_and_send_password if send_email
  end
  
  def reset_and_send_password
    password_for_email = self.randomize_password
    self.save!
    email = Mailer.create_password( self, password_for_email )
    Mailer.deliver email
  end
  
  def personal_list
    lists.first
  end
  
  def only_personal_list?
    (lists.size == 1)
  end
  
  def send_emails_about_personal_list
    EmailSubscription.find_by_list_id_and_user_id( personal_list, id ) ? true : false
  end
  
  def send_emails_about_personal_list=(send_email)
    if send_email == '1' && !send_emails_about_personal_list
      email_subscriptions.create :list => personal_list
    elsif send_email == '0' && send_emails_about_personal_list
      EmailSubscription.find_by_list_id_and_user_id( personal_list, id ).destroy
    end
  end
  
  # Subscribe by email to a lsit
  def subscribe_to_list( list )
    email_subscriptions.create :list => list
  end
  
  def has_added_to_list?( thing )
    case thing
    when List
      lists.detect { |users_list| users_list.children.direct.include?( thing ) }
    when Talk
      lists.detect { |users_list| users_list.talks.direct.include?( thing )}
    end
  end
  
  # This is used upon login to check whether the user should be asked to fill in more detail
  def needs_an_edit?
    return last_login ? false : true
  end


  private

  def set_password(new_password)  
    @password = Password.create(new_password)
    self.password_hash = @password
  end
  
end
