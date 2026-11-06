export type Role = "developer" | "admin" | "moderator" | "support" | "member";

export interface UserSummary {
  id: number;
  name: string;
  username: string;
  role: Role;
  level: number;
  avatar_url: string | null;
}

export interface Me extends Omit<UserSummary, "level"> {
  email: string;
  bio: string | null;
  birthday: string | null;
  xp: number;
  level: number;
  level_xp: number;
  level_need: number;
  joined_at: string;
}

export type FriendshipStatus = "none" | "friends" | "outgoing" | "incoming" | "self";

export interface FriendshipState {
  status: FriendshipStatus;
  id: number | null;
}

export interface Profile extends UserSummary {
  bio: string | null;
  birthday: string | null;
  xp: number;
  online: boolean;
  joined_at: string;
  friendship: FriendshipState | null;
}

export interface Preview {
  id: number;
  preview: string;
  author_name: string;
  created_at: string;
}

export interface SidebarGroup {
  conversation_id: number;
  kind: "lobby" | "group";
  name: string;
  avatar_url: string | null;
  unread: number;
  last_message: Preview | null;
  activity_at: string | null;
}

export interface SidebarFriend {
  user: UserSummary;
  online: boolean;
  conversation_id: number | null;
  unread: number;
  last_message: Preview | null;
  activity_at: string | null;
}

export interface SidebarData {
  groups: SidebarGroup[];
  friends: SidebarFriend[];
}

export interface Member {
  user: UserSummary;
  role: "owner" | "member";
  online: boolean;
  last_read_message_id: number;
}

export interface ConversationDetail {
  id: number;
  kind: "lobby" | "group" | "dm";
  name: string | null;
  avatar_url: string | null;
  owner_id: number | null;
  can_manage: boolean;
  can_moderate: boolean;
  member_count: number;
  members: Member[];
}

export interface ReactionSummary {
  emoji: string;
  count: number;
  user_ids: number[];
}

export interface ReplyRef {
  id: number;
  author_name: string;
  author_role: Role;
  preview: string;
}

export interface ChatMessage {
  id: number;
  conversation_id: number;
  author: UserSummary | null;
  body: string;
  image_url: string | null;
  reply_to: ReplyRef | null;
  reactions: ReactionSummary[];
  edited: boolean;
  deleted: boolean;
  client_id: string | null;
  created_at: string;
  /** Client-only: optimistic message waiting for the server. */
  pending?: boolean;
  failed?: boolean;
}

export interface MessagesPage {
  messages: ChatMessage[];
  has_more: boolean;
}

export type NotificationKind =
  | "friend_request"
  | "friend_accepted"
  | "mention"
  | "reply"
  | "level_up"
  | "group_added";

export interface AppNotification {
  id: number;
  kind: NotificationKind;
  actor: UserSummary | null;
  conversation_id: number | null;
  message_id: number | null;
  payload: Record<string, string | number | null>;
  read: boolean;
  created_at: string;
}

export interface NotificationsData {
  notifications: AppNotification[];
  unread_count: number;
}

export interface Stats {
  users: number;
  messages: number;
  online: number;
  groups: number;
}

export interface FriendRequest {
  id: number;
  user: UserSummary;
  created_at: string;
}

export interface SearchResult {
  user: UserSummary;
  online: boolean;
  friendship: FriendshipState;
}
