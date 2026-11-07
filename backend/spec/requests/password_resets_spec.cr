require "../spec_helper"

private def wait_for_mails(count : Int32) : Array(Saci::Mailer::Mail)
  deadline = Time.instant + 2.seconds
  until Saci::Mailer.deliveries.size >= count || Time.instant > deadline
    sleep 10.milliseconds
  end
  Saci::Mailer.deliveries
end

private def token_from(mail : Saci::Mailer::Mail) : String
  URI.decode_www_form(mail.body_text.match(/reset-password\?token=(\S+)/).not_nil![1])
end

describe "password reset API" do
  it "mails a single-use link, resets the password and ends other sessions" do
    with_app do |app|
      Saci::Mailer.clear_deliveries!
      bob = Fixtures.user("bob")
      old_device = Fixtures.browser(app, bob)
      anon = Browser.new(app)

      # Unknown address: same answer, nothing sent.
      anon.post("/api/password_resets", {email: "ninguem@test.local"}).status_code.should eq(200)
      anon.post("/api/password_resets", {email: " BOB@test.local "}).status_code.should eq(200)
      mail = wait_for_mails(1).first
      Saci::Mailer.deliveries.size.should eq(1)
      mail.to.should eq(["bob@test.local"])
      token = token_from(mail)

      # Asking again right away reuses the email already sent.
      anon.post("/api/password_resets", {email: "bob@test.local"}).status_code.should eq(200)
      sleep 50.milliseconds
      Saci::Mailer.deliveries.size.should eq(1)

      JSON.parse(anon.post("/api/password_resets/verify", {token: token}).body)["valid"].as_bool.should be_true
      JSON.parse(anon.post("/api/password_resets/verify", {token: "x" * 40}).body)["valid"].as_bool.should be_false

      # A weak password is refused without burning the link.
      anon.patch("/api/password_resets", {token: token, password: "123"}).status_code.should eq(422)
      res = anon.patch("/api/password_resets", {token: token, password: "nova-senha-forte"})
      res.status_code.should eq(200)
      JSON.parse(res.body)["user"]["username"].as_s.should eq("bob")
      anon.json("/api/session")["user"]["username"].as_s.should eq("bob") # signed in here

      # Used once, and every other session is gone.
      anon.patch("/api/password_resets", {token: token, password: "outra-senha-forte"}).status_code.should eq(422)
      old_device.json("/api/session")["user"].raw.should be_nil
      Browser.new(app).login("bob", "password123").status_code.should eq(401)
      Browser.new(app).login("bob", "nova-senha-forte").status_code.should eq(200)
    end
  end

  it "rejects expired links" do
    with_app do |app|
      Saci::Mailer.clear_deliveries!
      ana = Fixtures.user("ana")
      anon = Browser.new(app)
      anon.post("/api/password_resets", {email: "ana@test.local"})
      token = token_from(wait_for_mails(1).first)
      PasswordReset.where(user_id: ana.uid).update_all(expires_at: Time.utc - 1.minute)
      anon.patch("/api/password_resets", {token: token, password: "nova-senha-forte"}).status_code.should eq(422)
    end
  end

  it "signs other devices out when the password is changed in settings" do
    with_app do |app|
      cid = Fixtures.user("cid")
      laptop = Fixtures.browser(app, cid)
      phone = Fixtures.browser(app, cid)
      laptop.patch("/api/me/password", {current_password: "password123", password: "trocada-agora"}).status_code.should eq(200)
      laptop.json("/api/session")["user"]["username"].as_s.should eq("cid")
      phone.json("/api/session")["user"].raw.should be_nil
    end
  end
end
