# frozen_string_literal: true

require "rails_helper"

# Each bulk action button carries its own formaction, so the form that holds
# the checkboxes is posted to a path it was not rendered for. On a full page
# load jquery-ujs replaces the form's token with the one from the csrf-token
# meta tag, which counts for every path; the table the live search renders
# never goes through that, so it has to carry a usable token itself.
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

  # Swapping the driver resets the session, so this has to come before the
  # sign in below. Hooks of one context run in the order they are written.
  before do |example|
    driven_by(example.metadata[:driver]) if example.metadata[:driver]
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

  # page.all does not wait, so say how many rows the table must hold first,
  # or a table that has not rendered yet silently selects nothing.
  def select_listed_problems(count)
    expect(page).to have_css('input[name="problems[]"]', count: count)

    page.all('input[name="problems[]"]').each(&:check) # rubocop:disable Rails/FindEach
  end

  def problems_form
    find("#problem_table form")
  end

  it "merges the problems a search listed" do
    search_for("Searchable")

    select_listed_problems(2)

    accept_confirm { click_button "Merge" }

    expect(page).to have_content("2 errors have been merged.")

    expect(page).to have_no_content("already signed in")

    expect(Problem.count).to eq(2)
  end

  it "deletes the problems a search listed" do
    search_for("Searchable")

    select_listed_problems(2)

    accept_confirm { click_button "Delete" }

    expect(page).to have_content("2 errors will be deleted.")

    expect(Problem.count).to eq(1)
  end

  # jquery-ujs asks for confirmation from a delegated handler, so it only runs
  # once the button's own handlers are done. Nothing may point the form at the
  # button's path before that, or waving the dialog off would leave the form
  # aimed at an action the user just declined.
  it "leaves the form alone when the confirm is waved off" do
    visit problems_path

    select_listed_problems(3)

    target_before = problems_form[:action]

    dismiss_confirm { click_button "Delete" }

    expect(problems_form[:action]).to eq(target_before)

    expect(Problem.count).to eq(3)
  end

  it "merges without JavaScript", driver: :rack_test do
    visit problems_path

    select_listed_problems(3)

    click_button "Merge"

    expect(Problem.count).to eq(1)
  end

  it "merges problems straight after a page load" do
    visit problems_path

    select_listed_problems(3)

    accept_confirm { click_button "Merge" }

    expect(page).to have_content("3 errors have been merged.")
  end
end
