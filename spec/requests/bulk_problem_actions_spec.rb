# frozen_string_literal: true

require "rails_helper"

# The bulk action buttons rewrite the form's action, so the token the form is
# rendered with has to be accepted at every path they post to. See
# spec/system/bulk_problem_actions_spec.rb for the browser side of this.
RSpec.describe "Bulk problem actions", type: :request do
  let(:password) { "sekret-password-1234" }

  let(:user) { create(:user, password: password) }

  let(:errbit_app) { create(:app) }

  let!(:problem_1) { create(:problem, app: errbit_app) }

  let!(:problem_2) { create(:problem, app: errbit_app) }

  around do |example|
    original = ActionController::Base.allow_forgery_protection

    ActionController::Base.allow_forgery_protection = true

    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def form_containing(selector)
    response.parsed_body.css("form").find { |form| form.at_css(selector) }
  end

  def token_in(form)
    form.at_css('input[name="authenticity_token"]')["value"]
  end

  # Devise's test helper logs the user in again on every request, which drops
  # the CSRF token each time, so sign in the way a browser does.
  def sign_in_through_the_form
    get new_user_session_path

    post user_session_path, params: {
      authenticity_token: token_in(form_containing('input[name="user[email]"]')),
      user: {email: user.email, password: password}
    }
  end

  # errbit.js points the form at the clicked button's data-action and submits
  # it with the token the form already holds.
  def click_bulk_button(id, problems)
    get problems_path

    form = form_containing('input[name="problems[]"]')

    post form.at_css("##{id}")["data-action"], params: {
      authenticity_token: token_in(form),
      problems: problems.map { |problem| problem.id.to_s }
    }
  end

  before { sign_in_through_the_form }

  it "merges the selected problems" do
    expect { click_bulk_button("merge_problems", [problem_1, problem_2]) }
      .to change(Problem, :count).from(2).to(1)
  end

  it "resolves the selected problems" do
    click_bulk_button("resolve_problems", [problem_1])

    expect(problem_1.reload.resolved?).to be(true)
  end

  # This button is the one that posts to a path named differently from itself.
  it "deletes the selected problems" do
    expect { click_bulk_button("delete_problems", [problem_1]) }
      .to change(Problem, :count).from(2).to(1)
  end

  it "keeps the user signed in" do
    click_bulk_button("merge_problems", [problem_1, problem_2])

    2.times { follow_redirect! if response.redirect? }

    expect(flash[:alert]).to be_nil
  end
end
