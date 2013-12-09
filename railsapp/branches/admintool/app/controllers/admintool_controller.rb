class AdmintoolController < ApplicationController
  
  before_filter :ensure_user_is_logged_in
  before_filter :ensure_user_is_admin
  before_filter :find_user, :only => [:edit_crsid, :set_crsid, :delete_crsid]

  def search
    @search = params[:search]
    @users = search_all_users(@search)
  end

  def set_crsid
    modify_crsid(params[:crsid])
  end

  def delete_crsid
    modify_crsid(nil)
  end

  def find_admins
    @disable_search_box = true
    @heading2text = "Administrator = true"
    @users = User.find(:all, :conditions => ["administrator = 1"])
    render :template => "admintool/search"
  end

  private

  def ensure_user_is_admin
    unless User.current.administrator?
      raise "User must be administrator"
    end
    # Should never get here, but return correct boolean for filter chain anyway
    return User.current.administrator?
  end

  def find_user
    @user = User.find params[:id]
  end

  def modify_crsid(new_crsid)
    @user.crsid = new_crsid
    @user.save!
    redirect_to :action => 'edit_crsid', :id => @user.id
  end

  def search_all_users(search_term)
    return [] unless search_term && !search_term.empty?
    User.find(:all, :conditions => ["(name LIKE :search OR affiliation LIKE :search OR email LIKE :search OR crsid LIKE :search)",{:search => "%#{search_term.strip}%"}], :order => 'email ASC' )
  end

end
