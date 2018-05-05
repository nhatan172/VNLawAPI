class Api::V1::ReviewsController < Api::V1::ApplicationController
  acts_as_token_authentication_handler_for User, except: :index

  before_action :check_lawyer, :connected_to_lawyer, only: :create
  before_action :get_review, :get_lawyer, only: :update
  before_action :find_lawyer, only: :index

  def index
    response_all_reviews
  end

  def create
    @review = Review.new review_create_params
    authorize! :create, review

    begin
      review.save
      lawyer_votes = lawyer.votes
      lawyer_rate = lawyer.rate
      lawyer_rate = (lawyer_rate * lawyer_votes + params[:reviews][:star].to_f) / (lawyer_votes + 1)
      lawyer_votes += 1
      lawyer.update_attributes votes: lawyer_votes, rate: lawyer_rate

      update_wr

      response_create_success
    rescue ActiveRecord::RecordNotUnique
      response_create_failed
    end
  end

  def update
    authorize! :update, review
    old_rate_value = review.star
    if review.update_attributes review_update_params
      if params[:reviews][:star].to_f != old_rate_value
        lawyer_votes = lawyer.votes
        lawyer_rate = lawyer.rate
        lawyer_rate = (lawyer_rate * lawyer_votes - old_rate_value + params[:reviews][:star].to_f) / lawyer_votes
        lawyer.update_attributes rate: lawyer_rate

        update_wr
      end

      response_update_success
    else
      response_update_failed
    end
  end

  private

  attr_reader :reviews, :profile, :lawyer, :review, :room

  def response_update_success
    render json: {
      message: I18n.t("app.api.messages.update_success",
        authentication_keys: "review"),
      review: review.as_json(except: [:user_id, :lawyer_id,
        :created_at])
    }, status: :ok
  end

  def response_update_failed
    render json: {
      message: I18n.t("app.api.messages.update_failed",
        authentication_keys: "review")
    }, status: :unprocessable_entity
  end

  def response_create_success
    render json: {
      message: I18n.t("app.api.messages.create_success",
        authentication_keys: "review"),
      review: review.as_json(except: [:user_id, :lawyer_id])
    }, status: :ok
  end

  def response_create_failed
    render json: {
      message: I18n.t("app.api.messages.create_failed",
        authentication_keys: "review")
    }, status: :unprocessable_entity
  end

  def response_all_reviews
    render json: {
      reviews: lawyer.reviews.as_json(except:
        [:lawyer_id, :created_at])
    }, status: :ok
  end

  def cal_wr v, r, c
    return (v.to_f / (v + 10).to_f) * r + (10.to_f / (v + 10.to_f)) * c
  end

  def update_wr
    c = Review.average :star
    Lawyer.all.each do |lawyer|
      if lawyer.votes >= 10
        wr = cal_wr lawyer.votes, lawyer.rate, c
        lawyer.update_attributes wr: wr
      end
    end
  end

  def get_lawyer
    @lawyer = review.lawyer
  end

  def get_review
    @review = Review.find_by id: params[:id]

    return if review
    render json: {
      message: I18n.t("app.api.messages.not_found",
        authentication_keys: "review")
    }, status: :not_found
  end

  def find_lawyer
    @profile = Profile.find_by userName: params[:lawyer_id]
    @lawyer = Lawyer.find_by user_id: profile.user_id
    return if lawyer
    render json: {
      message: I18n.t("app.api.messages.not_found",
        authentication_keys: "lawyer")
    }, status: :not_found
  end

  def check_lawyer
    @lawyer = Lawyer.find_by id: params[:reviews][:lawyer_id]
    return if lawyer
    render json: {
      message: I18n.t("app.api.messages.not_found",
        authentication_keys: "lawyer")
    }, status: :not_found
  end

  def connected_to_lawyer
    @room = Room.where(user_id: current_user.id).where(
      lawyer_id: params[:reviews][:lawyer_id])
    params[:reviews][:user_id] = current_user.id
    return if room.length > 0
    render json: {
      message: I18n.t("app.api.messages.not_have_permission_create",
        authentication_keys: "review")
    }, status: :unauthorized
  end

  def review_update_params
    params.require(:reviews).permit Review::UPDATE_PARAMS
  end

  def review_create_params
    params.require(:reviews).permit Review::CREATE_PARAMS
  end
end
