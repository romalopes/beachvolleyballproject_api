class PagesController < ApplicationController
  allow_unauthenticated_access
  def home
    @categories = Category.all
    @skills = Skill.all
    @drills = Drill.all
  end

  def skills
    @categories = Category.order(:name)
    @skills = Skill.includes(:category).order(:title)
  end

  def skill
    @skill = Skill.includes(:category).find_by(slug: params[:id]) || Skill.includes(:category).find_by(id: params[:id])
    return render_not_found unless @skill

    @related_drills = @skill.drills.includes(skills: :category).order(:title)
  end

  def drills
    @drills = Drill.includes(skills: :category).order(:title)
  end

  def drill
    @drill = Drill.includes(skills: :category).find_by(slug: params[:id]) || Drill.includes(skills: :category).find_by(id: params[:id])
    return render_not_found unless @drill
  end

  def videos
    @videos = MediaAsset.includes(:drill).order(:title)
  end

  def training
    @sessions = TrainingSession.includes(drill: { skills: :category }).order(:scheduled_at)
  end

  def training_session
    @session = TrainingSession.includes(drill: { skills: :category }).find_by(id: params[:id])
    return render_not_found unless @session
  end

  def schedule
    @sessions = TrainingSession.includes(:drill).order(:scheduled_at)
  end

  def account
    require_authentication
    @account = Current.user&.account || Account.new
    @account.build_account_address unless @account.account_address
  end

  def update_account
    require_authentication

    if params[:commit_password].present?
      return update_password
    end

    @account = Current.user.account || Current.user.build_account
    @account.build_account_address unless @account.account_address

    if @account.update(account_params)
      redirect_to account_path, notice: "Account updated successfully."
    else
      render :account, status: :unprocessable_entity
    end
  end

  def update_password
    user = Current.user
    password_params = params[:account] || params

    unless user.authenticate(password_params[:current_password])
      flash[:alert] = "Current password is incorrect."
      return redirect_to account_path
    end

    new_password = password_params[:password]
    if new_password.blank? || new_password.length < 8
      flash[:alert] = "Password must be at least 8 characters."
      return redirect_to account_path
    end

    if new_password != password_params[:password_confirmation]
      flash[:alert] = "Password confirmation does not match."
      return redirect_to account_path
    end

    if user.update(password: new_password, password_confirmation: password_params[:password_confirmation])
      user.sessions.where.not(id: Current.session&.id).destroy_all
      flash[:notice] = "Password changed successfully."
    else
      flash[:alert] = user.errors.full_messages.join(". ")
    end

    redirect_to account_path
  end

  private

  def account_params
    params.require(:account).permit(
      :first_name, :last_name, :phone, :date_of_birth,
      account_address_attributes: %i[street_address city state postal_code country]
    )
  end

  def render_not_found
    render "pages/not_found", status: :not_found
  end
end
