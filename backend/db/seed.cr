# Demo data (idempotent): `saci db:seed`. Every account uses password123.
require "../src/app"

PASSWORD = "password123"

def seed_user(name : String, username : String, role : String, level : Int32, extra_xp : Int64, bio : String) : User
  if existing = User.find_by(username: username)
    return existing
  end
  xp = Levels.total_for(level) + extra_xp
  user = User.create!(
    name: name, username: username, email: "#{username}@braxy.local",
    password: PASSWORD, role: role, bio: bio, xp: xp, level: level,
  )
  puts "  user @#{username} (#{role}, nível #{level})"
  user
end

def befriend(a : User, b : User, accepted : Bool = true) : Nil
  return if Friendship.between(a.uid, b.uid)
  Friendship.create!(
    requester_id: a.uid, addressee_id: b.uid, pair_key: Friendship.pair_key(a.uid, b.uid),
    status: accepted ? "accepted" : "pending", accepted_at: accepted ? Time.utc : nil,
  )
end

def say(convo : Conversation, author : User, body : String, at : Time, reply_to : Message? = nil) : Message
  m = Message.create!(conversation_id: convo.cid, author_id: author.uid, body: body,
    reply_to_id: reply_to.try(&.mid), created_at: at, updated_at: at)
  convo.update_columns(last_message_id: m.mid, last_message_at: at)
  m
end

puts "Seeding Braxy..."
pedro  = seed_user("Pedro Henrique", "pedro", "developer", 33, 1_889, "Criador do Braxy e do Saci.")
marina = seed_user("Marina Costa", "marina", "admin", 28, 3_200, "Café, código e caos controlado.")
rafa   = seed_user("Rafael Lima", "rafa", "moderator", 22, 900, "Respeita o chat que o chat te respeita.")
julia  = seed_user("Júlia Alves", "julia", "support", 15, 450, "Dúvidas? Me chama!")
thiago = seed_user("Thiago Rocha", "thiago", "member", 8, 120, "Só passando.")
everyone = [pedro, marina, rafa, julia, thiago]

lobby = Conversation.lobby
everyone.each { |u| Membership.ensure!(lobby.cid, u.uid) }

[marina, rafa, julia, thiago].each { |u| befriend(pedro, u) }
befriend(marina, rafa)
befriend(thiago, julia, accepted: false)

if Message.where(conversation_id: lobby.cid).count == 0
  t = Time.utc - 2.hours
  m1 = say(lobby, marina, "Bom dia, pessoal! O Braxy voltou 🎉", t)
  say(lobby, rafa, "Finalmente! Saudade desse chat", t + 1.minute)
  say(lobby, thiago, "KKKKKKKKKKKKKKKKKKK", t + 2.minutes)
  say(lobby, pedro, "Agora rodando em Crystal com o Saci. Bem mais rápido 🚀", t + 3.minutes, reply_to: m1)
  say(lobby, julia, "Se alguém tiver dúvida de como usar, é só me marcar com @julia", t + 5.minutes)
  say(lobby, rafa, "@thiago menos KKK e mais conteúdo hein", t + 6.minutes)
  say(lobby, thiago, "pior q ele tá certo", t + 7.minutes)
  say(lobby, marina, "Lembrando: mensagens nos grupos dão XP. Bora subir de nível!", t + 9.minutes)
end

devs = Conversation.find_by(kind: "group", name: "Devs Braxy")
if devs.nil?
  devs = Conversation.create!(kind: "group", name: "Devs Braxy", owner_id: pedro.uid)
  Membership.ensure!(devs.cid, pedro.uid, "owner")
  [marina, rafa].each { |u| Membership.ensure!(devs.cid, u.uid) }
  t = Time.utc - 1.hour
  say(devs, pedro, "Deploy da v0.1 hoje à noite?", t)
  say(devs, marina, "Fechado. Já revisei as migrations", t + 2.minutes)
  say(devs, rafa, "Testei a moderação, tá tudo certo 👍", t + 4.minutes)
end

dm, _ = Conversation.find_or_create_dm(pedro.uid, marina.uid)
if Message.where(conversation_id: dm.cid).count == 0
  t = Time.utc - 30.minutes
  say(dm, marina, "Viu que a tela de login ficou linda?", t)
  say(dm, pedro, "Vi sim! A animação do painel ficou suave demais", t + 1.minute)
end

# Everyone has read everything that exists at seed time.
Membership.where("1 = 1").to_a.each do |m|
  convo = Conversation.find_by(id: m.conversation_id)
  if convo && (last = convo.last_message_id)
    m.update_columns(last_read_message_id: last) if m.last_read_message_id.not_nil! < last
  end
end

puts "Seed done. Login with any of: #{everyone.map { |u| "@#{u.username}" }.join(", ")} (senha: #{PASSWORD})"
