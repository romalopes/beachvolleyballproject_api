class AccountsController < ApplicationController
  def show
    require_authentication
    @account = Current.user&.account || Account.new
    @account.build_account_address unless @account.account_address
  end

  def update
    require_authentication

    if params[:commit_password].present?
      return update_password
    end

    @account = Current.user.account || Current.user.build_account
    @account.build_account_address unless @account.account_address

    if @account.update(account_params)
      redirect_to account_path, notice: "Account updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_password
    require_authentication
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
end