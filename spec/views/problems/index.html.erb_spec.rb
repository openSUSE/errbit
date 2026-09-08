# frozen_string_literal: true

require "rails_helper"

RSpec.describe "problems/index.html.erb", type: :view do
  let(:problem_1) { create(:problem) }

  let(:problem_2) { create(:problem, app: problem_1.app) }

  before do
    allow(view).to receive(:selected_problems).and_return([])
    allow(view).to receive(:all_errs).and_return(false)
    allow(view).to receive(:problems).and_return(
      Kaminari.paginate_array([problem_1, problem_2]).page(1).per(10)
    )
    allow(view).to receive(:params_sort).and_return("last_notice_at")
    allow(view).to receive(:params_order).and_return("asc")

    allow(controller).to receive(:current_user).and_return(create(:user))
  end

  describe "with problem" do
    before { problem_1 && problem_2 }

    it "should works" do
      render

      expect(rendered).to have_selector("div#problem_table.problem_table")
    end
  end

  describe "issue link" do
    # The link and the tracker it came from are recorded on the problem, so
    # it stays reachable after the app's issue tracker was removed.
    it "links the issue of a problem whose app has no issue tracker configured" do
      problem_1.update(issue_type: "github", issue_link: "https://github.com/errbit/errbit/issues/1347")

      render

      expect(rendered).to have_selector("td.issue_link a[href='https://github.com/errbit/errbit/issues/1347']")
    end
  end

  describe "show/hide resolved button behavior" do
    it "displays unresolved errors title and button" do
      allow(view).to receive(:all_errs).and_return(false)

      render

      expect(view.content_for(:title)).to match "Unresolved Errors"
      expect(view.content_for(:action_bar)).to have_link "show resolved"
    end

    it "displays all errors title and button" do
      allow(view).to receive(:all_errs).and_return(true)

      render

      expect(view.content_for(:title)).to match "All Errors"
      expect(view.content_for(:action_bar)).to have_link "hide resolved"
    end
  end
end
