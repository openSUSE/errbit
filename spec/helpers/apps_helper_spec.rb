# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppsHelper, type: :helper do
  describe "#masked_api_key" do
    it "keeps the first half of the key and replaces the rest with X" do
      expect(helper.masked_api_key("98d8f6a1c3b2e4d5")).to eq("98d8f6a1XXXXXXXX")
    end

    it "does not reveal more than half of an odd-length key" do
      expect(helper.masked_api_key("abcde")).to eq("abXXX")
    end

    it "is blank for a missing key" do
      expect(helper.masked_api_key(nil)).to eq("")
    end

    it "does not raise for a key that is not a string" do
      expect(helper.masked_api_key(1234)).to eq("12XX")
    end
  end
end
