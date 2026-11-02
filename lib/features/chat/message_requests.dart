// Message requests (direct chats started from user search — see
// functions/src/directMessages.ts) as the chat lists see them.

/// A request [uid] still has to answer, or has declined. These stay out of
/// the inbox and its unread badges and live under Message requests instead.
bool isRequestToMe(Map<String, dynamic> room, String uid) =>
    room['requestTo'] == uid &&
    (room['requestStatus'] == 'pending' || room['requestStatus'] == 'declined');

/// A search chat opened but never written in — nothing to list yet.
bool isEmptyDirectChat(Map<String, dynamic> room) =>
    room['isDirect'] == true &&
    ((room['lastMessageSenderId'] as String?) ?? '').isEmpty;

/// True when the room doesn't belong in [uid]'s main chat list.
bool hiddenFromInbox(Map<String, dynamic> room, String uid) =>
    isRequestToMe(room, uid) || isEmptyDirectChat(room);
