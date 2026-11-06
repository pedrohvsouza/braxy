import { useUi } from "../store/ui";
import { RequestsModal } from "./friends/RequestsModal";
import { CreateGroupModal } from "./groups/CreateGroupModal";
import { GroupInfoModal } from "./groups/GroupInfoModal";
import { ProfileModal } from "./profile/ProfileModal";
import { SettingsModal } from "./profile/SettingsModal";

export function Modals() {
  const modal = useUi((s) => s.modal);
  switch (modal?.kind) {
    case "profile":
      return <ProfileModal key={modal.username} username={modal.username} />;
    case "settings":
      return <SettingsModal />;
    case "createGroup":
      return <CreateGroupModal />;
    case "groupInfo":
      return <GroupInfoModal conversationId={modal.conversationId} />;
    case "requests":
      return <RequestsModal />;
    default:
      return null;
  }
}
