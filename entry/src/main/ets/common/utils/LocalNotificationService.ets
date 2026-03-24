import notificationManager from '@ohos.notificationManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from './AppContext';

const TAG: string = 'LocalNotificationService';
const DEFAULT_NOTIFICATION_TITLE: string = '新通知';
const DEFAULT_NOTIFICATION_BODY: string = '你有一条新消息';

function decodeHtmlEntities(text: string): string {
  let result: string = text;
  result = result.replace(/&nbsp;/g, ' ');
  result = result.replace(/&lt;/g, '<');
  result = result.replace(/&gt;/g, '>');
  result = result.replace(/&amp;/g, '&');
  result = result.replace(/&quot;/g, '"');
  result = result.replace(/&#39;/g, '\'');
  result = result.replace(/&#x27;/g, '\'');
  return result;
}

export class LocalNotificationService {
  private static instance: LocalNotificationService | null = null;

  private initialized: boolean = false;
  private permissionPrompted: boolean = false;
  private notificationsEnabled: boolean | null = null;

  private constructor() {
  }

  static getInstance(): LocalNotificationService {
    if (LocalNotificationService.instance === null) {
      LocalNotificationService.instance = new LocalNotificationService();
    }
    return LocalNotificationService.instance;
  }

  private async ensureInitialized(): Promise<void> {
    if (this.initialized) {
      return;
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Add notification slot skipped: %{public}s', JSON.stringify(err));
    }
    this.initialized = true;
  }

  private async checkNotificationsEnabled(promptIfDisabled: boolean): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      this.notificationsEnabled = enabled;
      if (enabled || !promptIfDisabled || this.permissionPrompted) {
        return enabled;
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Check notification enabled failed: %{public}s', JSON.stringify(err));
      if (!promptIfDisabled || this.permissionPrompted) {
        return false;
      }
    }

    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      return false;
    }

    this.permissionPrompted = true;
    try {
      await notificationManager.requestEnableNotification(ctx);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Request enable notification failed: %{public}s', JSON.stringify(err));
    }

    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      this.notificationsEnabled = enabled;
      return enabled;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Re-check notification enabled failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  private sanitizeText(text: string, fallback: string, maxLength: number): string {
    const raw: string = text !== undefined && text !== null ? text : '';
    let normalized: string = raw.replace(/<br\s*\/?>/gi, '\n');
    normalized = normalized.replace(/<[^>]*>/g, ' ');
    normalized = decodeHtmlEntities(normalized);
    normalized = normalized.replace(/\s+/g, ' ').trim();
    if (normalized.length === 0) {
      normalized = fallback;
    }
    if (normalized.length > maxLength) {
      normalized = `${normalized.substring(0, maxLength).trim()}…`;
    }
    return normalized;
  }

  async show(title: string, body: string, id: number = 0): Promise<void> {
    await this.ensureInitialized();
    let enabled: boolean = this.notificationsEnabled === true;
    if (!enabled) {
      enabled = await this.checkNotificationsEnabled(false);
    }
    if (!enabled) {
      enabled = await this.checkNotificationsEnabled(true);
    }
    if (!enabled) {
      hilog.info(0x0000, TAG, 'Notification disabled, skip publish');
      return;
    }

    const request: notificationManager.NotificationRequest = {
      id: id > 0 ? id : Date.now() % 1000000,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: this.sanitizeText(title, DEFAULT_NOTIFICATION_TITLE, 72),
          text: this.sanitizeText(body, DEFAULT_NOTIFICATION_BODY, 160)
        }
      }
    };

    try {
      await notificationManager.publish(request);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Publish notification failed: %{public}s', JSON.stringify(err));
    }
  }
}
