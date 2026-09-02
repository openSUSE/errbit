# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrbitGithubAppPlugin::IssueTracker do
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }

  let(:tracker) { described_class.new(github_repo: "errbit/errbit") }

  before do
    allow(Errbit::Config).to receive_messages(
      github_app_id: "12345",
      github_app_private_key: rsa_key.to_pem
    )
  end

  it "is registered as the github_app issue tracker" do
    expect(ErrbitPlugin::Registry.issue_trackers["github_app"]).to eq(described_class)
  end

  describe "#errors" do
    it "is configured with app credentials and a repository" do
      expect(tracker.errors).to be_empty

      expect(tracker.configured?).to eq(true)
    end

    it "requires the GitHub App credentials" do
      allow(Errbit::Config).to receive(:github_app_private_key).and_return(nil)

      expect(tracker.errors).to eq(
        [[:base, "You must set the GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY environment variables."]]
      )
    end

    it "accepts the path of a .pem file as the private key" do
      Tempfile.create(["github_app", ".pem"]) do |pem_file|
        pem_file.write(rsa_key.to_pem)
        pem_file.flush

        allow(Errbit::Config).to receive(:github_app_private_key)
          .and_return(pem_file.path)

        expect(tracker.errors).to be_empty
      end
    end

    it "rejects a private key path that cannot be read" do
      allow(Errbit::Config).to receive(:github_app_private_key)
        .and_return("/nonexistent/github_app.pem")

      expect(tracker.errors).to eq([[:base, described_class::NOT_A_PRIVATE_KEY]])
    end

    it "rejects a private key that is not a PEM, like the App's client secret" do
      allow(Errbit::Config).to receive(:github_app_private_key)
        .and_return("0123456789abcdef0123456789abcdef01234567")

      expect(tracker.errors).to eq([[:base, described_class::NOT_A_PRIVATE_KEY]])

      expect(tracker.configured?).to eq(false)
    end

    it "rejects a public key" do
      allow(Errbit::Config).to receive(:github_app_private_key)
        .and_return(rsa_key.public_key.to_pem)

      expect(tracker.errors).to eq([[:base, described_class::NOT_A_PRIVATE_KEY]])
    end

    it "parses the private key only once per tracker" do
      allow(OpenSSL::PKey::RSA).to receive(:new).and_call_original

      2.times { tracker.errors }

      expect(OpenSSL::PKey::RSA).to have_received(:new).once
    end

    it "requires a repository" do
      expect(described_class.new({}).errors).to eq(
        [[:base, "You must specify your GitHub repository url."]]
      )
    end
  end

  describe "#url" do
    it "points at the issues of the repository" do
      expect(tracker.url).to eq("https://github.com/errbit/errbit/issues")
    end
  end

  context "talking to GitHub" do
    let(:app_client) { instance_double(Octokit::Client) }
    let(:issues_client) { instance_double(Octokit::Client) }

    let(:app_jwts) { [] }

    before do
      allow(Octokit::Client).to receive(:new) do |options|
        if options[:bearer_token]
          app_jwts << options[:bearer_token]

          app_client
        else
          expect(options[:access_token]).to eq("ghs_installation_token")

          issues_client
        end
      end

      allow(app_client).to receive(:find_repository_installation)
        .with("errbit/errbit").and_return(double(id: 42))

      allow(app_client).to receive(:create_app_installation_access_token)
        .with(42, repositories: ["errbit"], permissions: {issues: "write"})
        .and_return(double(token: "ghs_installation_token"))
    end

    describe "#create_issue" do
      before do
        allow(issues_client).to receive(:create_issue)
          .and_return(double(html_url: "https://github.com/errbit/errbit/issues/1347"))
      end

      it "creates the issue with a repo-scoped installation token and returns its URL" do
        url = tracker.create_issue("title", "body", user: {"github_login" => "biow0lf"})

        expect(url).to eq("https://github.com/errbit/errbit/issues/1347")

        expect(issues_client).to have_received(:create_issue)
          .with("errbit/errbit", "title", "body\n\n_Reported by @biow0lf via Errbit_")
      end

      it "authenticates as the GitHub App with a signed JWT" do
        tracker.create_issue("title", "body", user: {})

        payload, header = JWT.decode(app_jwts.fetch(0), rsa_key.public_key, true, algorithm: "RS256")

        expect(header["alg"]).to eq("RS256")
        expect(payload["iss"]).to eq("12345")
        expect(payload["exp"]).to be > Time.now.to_i
      end

      it "attributes the issue to the user's name without a github login" do
        tracker.create_issue("title", "body", user: {"name" => "Jane Doe"})

        expect(issues_client).to have_received(:create_issue)
          .with("errbit/errbit", "title", "body\n\n_Reported by Jane Doe via Errbit_")
      end

      it "explains when the App is not installed on the repository" do
        allow(app_client).to receive(:find_repository_installation)
          .and_raise(Octokit::NotFound)

        expect { tracker.create_issue("title", "body", user: {}) }
          .to raise_error(described_class::Error, /not installed on errbit\/errbit/)
      end

      it "explains when GITHUB_APP_PRIVATE_KEY holds the client secret instead of a PEM key" do
        allow(Errbit::Config).to receive(:github_app_private_key)
          .and_return("0123456789abcdef0123456789abcdef01234567")

        expect { tracker.create_issue("title", "body", user: {}) }
          .to raise_error(described_class::Error, /Generate a private key/)
      end

      it "explains when GitHub rejects the App credentials" do
        allow(app_client).to receive(:find_repository_installation)
          .and_raise(Octokit::Unauthorized)

        expect { tracker.create_issue("title", "body", user: {}) }
          .to raise_error(described_class::Error, /GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY/)
      end
    end

    describe "#close_issue" do
      it "closes the issue behind the link and returns its URL" do
        allow(issues_client).to receive(:close_issue)
          .with("errbit/errbit", "1347")
          .and_return(double(html_url: "https://github.com/errbit/errbit/issues/1347"))

        url = tracker.close_issue("https://github.com/errbit/errbit/issues/1347", user: {})

        expect(url).to eq("https://github.com/errbit/errbit/issues/1347")
      end
    end
  end
end
