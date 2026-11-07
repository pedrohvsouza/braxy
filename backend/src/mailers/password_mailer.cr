require "html"

class PasswordMailer < Saci::Mailer::Base
  default_from ENV["MAIL_FROM"]? || "Braxy <no-reply@braxy.local>"

  def self.reset(user : User, url : String) : Saci::Mailer::Mail
    name = user.name.to_s
    minutes = PasswordReset::TTL.total_minutes.to_i
    mail(to: user.email.not_nil!, subject: "Redefinir sua senha do Braxy") do |format|
      format.text do
        <<-TEXT
        Olá, #{name}!

        Recebemos um pedido para redefinir a senha da sua conta @#{user.username} no Braxy.
        Abra o link abaixo para escolher uma senha nova (vale por #{minutes} minutos e só uma vez):

        #{url}

        Se não foi você, ignore este e-mail: sua senha continua a mesma.
        TEXT
      end
      format.html do
        <<-HTML
        <div style="font-family:Poppins,Arial,sans-serif;max-width:480px;margin:auto;color:#1b1c27">
          <h2 style="color:#7b4dff">Redefinir sua senha</h2>
          <p>Olá, #{HTML.escape(name)}!</p>
          <p>Recebemos um pedido para redefinir a senha da sua conta <b>@#{HTML.escape(user.username.to_s)}</b> no Braxy.</p>
          <p><a href="#{HTML.escape(url)}" style="display:inline-block;padding:10px 18px;border-radius:8px;background:#7b4dff;color:#fff;text-decoration:none">Escolher nova senha</a></p>
          <p style="font-size:13px;color:#555">O link vale por #{minutes} minutos e só pode ser usado uma vez.
          Se não foi você, ignore este e-mail: sua senha continua a mesma.</p>
        </div>
        HTML
      end
    end
  end
end
