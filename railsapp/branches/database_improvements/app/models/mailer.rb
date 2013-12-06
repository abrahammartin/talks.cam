class Mailer < ActionMailer::Base
  
  include ActionController::UrlWriter
  HOSTROOTURL = ActionController::Base.asset_host
  
  # HOST is used by legacy code and must not contain the protocol prefix
  default_url_options[:host] = HOST = HOSTROOTURL.sub(/^[a-z]+:\/\//,'')

  # FIXME: Refactor into class variables and set in environment.rb
  FROM = 'noreply@talks.cam.ac.uk'

  
  # The periodic mailshots
  
  def self.send_mailshots
    send_weekly_list if Time.now.wday == 0
    send_daily_list
  end
  
  def self.send_weekly_list
    EmailSubscription.find(:all).each do |subscription|
      mail = create_weekly_list( subscription )
      if mail.parts.first.body =~ /\(No talks\)/
        logger.info "No talks, so not sending message"
      else
        deliver mail
      end
    end
  end
  
  def self.send_daily_list
    EmailSubscription.find(:all).each do |subscription|
      mail = create_daily_list( subscription )
      if mail.parts.first.body =~ /\(No talks\)/
        logger.info "No talks, so not sending message"
      else
        deliver mail
      end
    end
  end
  
  # The mails
  
  def password(user, password, url = "http://talks.cam.ac.uk/login/other_users")
# XXX do we need filter_param_logging or does it only apply to controllers?
    @subject    = 'Your talks.cam password'
    @body       = { :user => user, :url => login_url(:action => 'other_users'), :password => password, :hostrooturl => HOSTROOTURL }
    @recipients = user.email
    @from       = FROM
    @sent_on    = Time.now
    @headers    = {}
  end
  
  def speaker_invite(user, talk)
### XXX  aargh @user.crsid gets corrupted by speaker invitage !!?? though any self-edit would, actually??? seems if last_login != null it doesn't get corrupted?? ###
    if talk.organiser.name && talk.organiser.name.length > 0 # XXX empty?
      organisername = talk.organiser.name
    else
      organisername = talk.organiser.email
    end
    passwordreseturl = "#{HOSTROOTURL}/login/send_password?email=#{user.email}"
    @subject    = 'Giving a talk in Cambridge'
    @body       = { :user => user, :url => talk_url(:id => talk.id, :action => 'edit'), :talk => talk, :hostrooturl => HOSTROOTURL, :passwordreseturl => passwordreseturl, :organisername => organisername }
    @recipients = user.email
    @cc         = talk.organiser.email if talk.organiser && talk.organiser.email
    @from       = FROM
    @sent_on    = Time.now
    @headers    = {}
  end
  
  def daily_list( subscription )
    logger.info "Creating daily message about #{subscription.list.name} for #{subscription.user.email}"
    set_common_variables( subscription )
    parameters = { :controller => 'show', :id => subscription.list.id, :seconds_after_today => 1.day, :seconds_before_today => 0,:username => subscription.user.name, :action => 'email' }
    @subject    = "[Talks.cam] Today's talks: #{subscription.list.name}"
    @body[:text] = get_list( parameters )
  end
  
  def weekly_list( subscription )
    logger.info "Creating weekly message about #{subscription.list.name} for #{subscription.user.email}"
    set_common_variables( subscription )
    @subject    = "[Talks.cam] This week's talks: #{subscription.list.name}"
    parameters = { :controller => 'show', :id => subscription.list.id,:seconds_after_today => 1.week, :seconds_before_today => 0,:username => subscription.user.name, :action => 'email' }
    @body[:text] = get_list( parameters )
  end
  
  def talk_tickle( tickle )
    talk = tickle.about
    @subject = "[Talks.cam] A talk that you might be interested in"
    @body = { :tickle => tickle,
      :talk => talk,
      :talk_url => talk_url(:id => talk.id),
      :talk_ics_url => talk_url(:id => talk.id, :action => 'vcal' ),
      :add_to_list_url => include_talk_url(:action => 'create', :child => talk)
    }
    @recipients = tickle.recipient_email
    @cc = tickle.sender_email
    @from = FROM
    @send_on = Time.now
    @headers = {}
  end
  
  def list_tickle( tickle )
    list = tickle.about
    talks = list.talks.find(:all, :limit => 5, :order => 'start_time ASC', :conditions => ['start_time > ?', Time.now.at_beginning_of_day ])
    @subject = "[Talks.cam] A list that you might be interested in"
    @body = { :tickle => tickle,
      :list => list,
      :talks => talks,
      :list_url => list_url(:id => list.id),
      :list_webcal_url => list_url(:id => list.id, :action => 'ics', :only_path => false, :protocol => 'webcal' ),
      :add_to_list_url => include_list_url(:action => 'create', :child => list)
    }
    @recipients = tickle.recipient_email
    @cc = tickle.sender_email
    @from = FROM
    @send_on = Time.now
    @headers = {}
  end
  
  private
  
  def set_common_variables( subscription )

    @body       = { :user => subscription.user, :host => HOST }
    @recipients = subscription.user.email
    @from       = FROM
    @sent_on    = Time.now
    @headers    = {}
  end
  
  def get_list( options )
    session = ActionController::Integration::Session.new
    session.host! HOST
    session.get session.url_for(options)
    session.response.body
  end
end
