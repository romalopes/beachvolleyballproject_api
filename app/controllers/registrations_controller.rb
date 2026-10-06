class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if contact_name_present? && User.transaction { @user.save && create_account! }
      @user.add_role(:player)
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome to BVB Hub"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

    def registration_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation)
    end

    def user_params
      registration_params.slice(:email_address, :password, :password_confirmation)
    end

    def create_account!
      Account.create!(user: @user, contact_detail: ContactDetail.new(
        first_name: registration_params[:first_name], last_name: registration_params[:last_name], email: @user.email_address
      ))
    end

    def contact_name_present?
      return true if registration_params[:first_name].to_s.strip.present? && registration_params[:last_name].to_s.strip.present?

      @user.errors.add(:base, "First name and last name are required.")
      false
    end
end
