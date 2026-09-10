# frozen_string_literal: true

require "rails_helper"

# The bulk action buttons share the form that holds the checkboxes and
# errbit.js points that form at the clicked button's path. On a full page load
# jquery-ujs replaces the form's token with the one from the csrf-token meta
# tag, which counts for every path; the table the live search renders never
# goes through that, so it has to carry a usable token itself.
RSpec.describe "Bulk problem actions", type: :system, retry: 3 do
  let(:password) { "sekret-password-1234" }

  let!(:user) { create(:user, password: password) }

  let(:errbit_app) { create(:app) }

  let!(:problem_1) { create(:problem, app: errbit_app, message: "Searchable one") }

  let!(:problem_2) { create(:problem, app: errbit_app, message: "Searchable two") }

  let!(:untouched_problem) { create(:problem, app: errbit_app, message: "Unrelated problem") }

  around do |example|
    original = ActionController::Base.allow_forgery_protection

    ActionController::Base.allow_forgery_protection = true

    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  # Devise's test helper logs the user in again on every request, which drops
  # the CSRF token each time, so sign in the way a person does.
  before do
    visit new_user_session_path

    fill_in "user_email", with: user.email

    fill_in "user_password", with: password

    click_button "Sign in"

    expect(page).to have_current_path(root_path)
  end

  def search_for(term)
    visit problems_path

    fill_in "search", with: term

    find("#search").send_keys(:enter)

    expect(page).to have_no_content("Unrelated problem")
  end

  def select_listed_problems
    page.all('input[name="problems[]"]').each(&:check)
  end

  it "merges the problems a search listed" do
    search_for("Searchable")

    select_listed_problems

    accept_confirm { click_button "Merge" }

    expect(page).to have_content("2 errors have been merged.")

    expect(page).to have_no_content("already signed in")

    expect(Problem.count).to eq(2)
  end

  it "deletes the problems a search listed" do
    search_for("Searchable")

    select_listed_problems

    accept_confirm { click_button "Delete" }

    expect(page).to have_content("2 errors will be deleted.")

    expect(page).to have_no_content("already signed in")
  end

  it "merges problems straight after a page load" do
    visit problems_path

    select_listed_problems

    accept_confirm { click_button "Merge" }

    expect(page).to have_content("3 errors have been merged.")
  end
end
