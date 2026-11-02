const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");

initializeApp();

// ทำงานเมื่อมีเอกสารใหม่ในกล่องแจ้งเตือนผู้ใช้ แล้วส่ง FCM ไปยังอุปกรณ์ที่ลงทะเบียนไว้
exports.sendChatPushNotification = onDocumentCreated(
  "users/{uid}/notifications/{notificationId}",
  async (event) => {
    const notification = event.data?.data();
    if (!notification || ![
      "chat_message",
      "join_request_received",
      "join_request_accepted",
      "post_like",
      "new_follower",
      "post_comment",
      "group_chat_message",
      "admin_report",
      "post_removed",
    ].includes(notification.type)) return;

    const uid = event.params.uid;
    const devices = await getFirestore()
      .collection("users")
      .doc(uid)
      .collection("devices")
      .get();

    if (devices.empty) {
      logger.info("No registered devices for notification recipient", {uid});
      return;
    }

    const senderName = notification.senderName || "ผู้เล่น";
    let title;
    let fallbackBody;
    switch (notification.type) {
      case "post_like":
        title = notification.reaction === "like"
          ? `${senderName} ถูกใจโพสต์ของคุณ`
          : `${senderName} แสดงความรู้สึก ${notification.reaction || ""} บนโพสต์ของคุณ`;
        fallbackBody = "มีคนแสดงความรู้สึกบนโพสต์ของคุณ";
        break;
      case "new_follower":
        title = `มีผู้ติดตามใหม่: ${senderName}`;
        fallbackBody = "แตะเพื่อดูโปรไฟล์ผู้ติดตาม";
        break;
      case "post_comment":
        title = `${senderName} แสดงความคิดเห็นในโพสต์ของคุณ`;
        fallbackBody = "มีความคิดเห็นใหม่ในโพสต์ของคุณ";
        break;
      case "group_chat_message":
        title = `${senderName} ส่งข้อความในกลุ่ม ${notification.groupName || "กลุ่มแชต"}`;
        fallbackBody = "มีข้อความใหม่ในกลุ่มแชต";
        break;
      case "join_request_accepted":
        title = "คำขอเข้าร่วมได้รับการตอบรับ";
        fallbackBody = "คำขอเข้าร่วมทีมของคุณได้รับการตอบรับ";
        break;
      case "admin_report":
        title = "มีรายงานโพสต์ใหม่";
        fallbackBody = "กรุณาตรวจสอบรายงานในหน้าจัดการระบบ";
        break;
      case "post_removed":
        title = "โพสต์ของคุณถูกลบ";
        fallbackBody = "โพสต์ถูกลบเนื่องจากมีเนื้อหาที่ไม่เหมาะสม";
        break;
      case "join_request_received":
        title = `มีคำขอเข้าร่วมทีมจาก ${senderName}`;
        fallbackBody = "แตะเพื่อดูคำขอและตอบรับสมาชิกทีม";
        break;
      default:
        title = notification.senderName
          ? `ข้อความใหม่จาก ${notification.senderName}`
          : "ข้อความใหม่ใน Game Party";
        fallbackBody = "แตะเพื่อเปิดบทสนทนา";
    }
    const body = String(notification.body || fallbackBody).slice(0, 180);
    const messaging = getMessaging();

    await Promise.all(devices.docs.map(async (device) => {
      const token = device.data().token;
      if (typeof token !== "string" || token.length === 0) return;

      try {
        await messaging.send({
          token,
          notification: {title, body},
          data: {
            type: notification.type,
            chatId: String(notification.chatId || ""),
            postId: String(notification.postId || ""),
            groupId: String(notification.groupId || ""),
            groupName: String(notification.groupName || ""),
            reaction: String(notification.reaction || ""),
            messageId: String(notification.messageId || ""),
            senderUid: String(notification.senderUid || ""),
            notificationId: event.params.notificationId,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "game_party_notifications",
              sound: "default",
            },
          },
          apns: {
            payload: {aps: {sound: "default", badge: 1}},
          },
        });
      } catch (error) {
        const code = error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          await device.ref.delete();
          logger.info("Removed expired FCM token", {uid, deviceId: device.id});
          return;
        }
        logger.error("Could not send chat push notification", {uid, code});
        throw error;
      }
    }));
  },
);


// ทำงานเมื่อมีรายงานใหม่สถานะ pending แล้วสร้าง admin_report ให้ inbox ของแอดมินทุกคน
exports.notifyAdminsOfPostReport = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const report = event.data?.data();
    if (!report || report.status !== "pending") return;
    const db = getFirestore();
    const admins = await db.collection("admins").get();
    if (admins.empty) {
      logger.warn("No admins configured for post reports");
      return;
    }
    const batch = db.batch();
    for (const admin of admins.docs) {
      const notice = db.collection("users").doc(admin.id)
        .collection("notifications").doc();
      batch.set(notice, {
        type: "admin_report",
        body: `${report.reporterName || "ผู้ใช้"} รายงานโพสต์ของ ${report.postOwnerName || "ผู้ใช้"}: ${report.reason || "ไม่ได้ระบุเหตุผล"}`,
        reportId: event.params.reportId,
        createdAt: new Date(),
        isRead: false,
      });
    }
    await batch.commit();
  },
);
