require 'test_helper'

class ActivitiesControllerTest < ActionController::TestCase
  setup do
    @activity = activities(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:activities)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create activity" do
    assert_difference('Activity.count') do
      post :create, activity: { activity_type: @activity.activity_type, batch_id: @activity.batch_id, destination_facility: @activity.destination_facility, destination_location: @activity.destination_location, end_time: @activity.end_time, nomination_id: @activity.nomination_id, shipper: @activity.shipper, source_location: @activity.source_location, start_time: @activity.start_time, volume: @activity.volume }
    end

    assert_redirected_to activity_path(assigns(:activity))
  end

  test "should show activity" do
    get :show, id: @activity
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @activity
    assert_response :success
  end

  test "should update activity" do
    patch :update, id: @activity, activity: { activity_type: @activity.activity_type, batch_id: @activity.batch_id, destination_facility: @activity.destination_facility, destination_location: @activity.destination_location, end_time: @activity.end_time, nomination_id: @activity.nomination_id, shipper: @activity.shipper, source_location: @activity.source_location, start_time: @activity.start_time, volume: @activity.volume }
    assert_redirected_to activity_path(assigns(:activity))
  end

  test "should destroy activity" do
    assert_difference('Activity.count', -1) do
      delete :destroy, id: @activity
    end

    assert_redirected_to activities_path
  end
end
