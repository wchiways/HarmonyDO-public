import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiscourseNotification } from '../../models/Notification';
import { User } from '../../models/User';
import { AuthService } from '../auth/AuthService';
import { ApiClient } from '../network/ApiClient';
import { LocalNotificationService } from '../../common/utils/LocalNotificationService';
import { MessageBusMessage, MessageBusService } from './MessageBusService';
import { PreloadedDataService } from './PreloadedDataService';

const TAG: string = 'NotificationTrackingService';

export class NotificationTrackingState {
  userId: number = 0;
  allUnread: number = 0;
  unread: number = 0;
  highPriority: number = 0;
  channelPosition: number = 0;

  constructor() {
  }
}

class NotificationPreviewCounts {
  allUnread: number = 0;
  highPriority: number = 0;

  constructor() {
  }
}

export class NotificationTrackingService {
  private static instance: NotificationTrackingService | null = null;

  private startInFlight: Promise<void> | null = null;
  private subscribedChannel: string = '';
  private channelCallback: ((message: MessageBusMessage) => void) | null = null;
  private alertSubscribedChannel: string = '';
  private alertChannelCallback: ((message: MessageBusMessage) => void) | null = null;
  private startedUserId: number = 0;
  private listeners: (() => void)[] = [];
  private notifyScheduled: boolean = false;
  private state: NotificationTrackingState = new NotificationTrackingState();

  private constructor() {
  }

  static getInstance(): NotificationTrackingService {
    if (NotificationTrackingService.instance === null) {
      NotificationTrackingService.instance = new NotificationTrackingService();
    }
    return NotificationTrackingService.instance;
  }

  addListener(listener: () => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        return;
      }
    }
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const next: (() => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  private notifyListeners(): void {
    if (this.notifyScheduled) {
      return;
    }
    this.notifyScheduled = true;
    setTimeout(() => {
      this.notifyScheduled = false;
      for (let i = 0; i < this.listeners.length; i++) {
        try {
          this.listeners[i]();
        } catch (_) {
        }
      }
    }, 0);
  }

  getAllUnreadCount(): number {
    return this.state.allUnread;
  }

  getState(): NotificationTrackingState {
    const copy: NotificationTrackingState = new NotificationTrackingState();
    copy.userId = this.state.userId;
    copy.allUnread = this.state.allUnread;
    copy.unread = this.state.unread;
    copy.highPriority = this.state.highPriority;
    copy.channelPosition = this.state.channelPosition;
    return copy;
  }

  syncStateFromCurrentUser(user: User | null, notify: boolean = true): void {
    this.applyUserState(user, notify);
  }

  syncStateFromNotificationPreview(notifications: DiscourseNotification[], seenNotificationId: number = 0): void {
    const auth: AuthService = AuthService.getInstance();
    const currentUser: User | null = auth.getCurrentUser();
    if (currentUser === null || currentUser.id <= 0) {
      return;
    }
    const counts: NotificationPreviewCounts = this.buildPreviewCounts(notifications);
    if (!this.applyPreviewCounts(currentUser, counts, seenNotificationId, true)) {
      return;
    }
    auth.setCurrentUser(currentUser, true);
    ApiClient.getInstance().setCachedCurrentUser(currentUser);
    this.applyUserState(currentUser, true);
  }

  resetState(notify: boolean = true): void {
    this.applyUserState(null, notify);
  }

  async start(): Promise<void> {
    if (this.startInFlight !== null) {
      return await this.startInFlight;
    }
    this.startInFlight = this.startInternal();
    try {
      await this.startInFlight;
    } finally {
      this.startInFlight = null;
    }
  }

  private shouldNotifyCurrentUserUpdate(previousUser: User | null, nextUser: User): boolean {
    if (previousUser === null) {
      return true;
    }
    return previousUser.id !== nextUser.id
      || previousUser.allUnreadNotificationsCount !== nextUser.allUnreadNotificationsCount
      || previousUser.unreadNotifications !== nextUser.unreadNotifications
      || previousUser.unreadHighPriorityNotifications !== nextUser.unreadHighPriorityNotifications
      || previousUser.notificationChannelPosition !== nextUser.notificationChannelPosition;
  }

  stop(): void {
    if (this.subscribedChannel.length > 0 && this.channelCallback !== null) {
      MessageBusService.getInstance().unsubscribe(this.subscribedChannel, this.channelCallback);
    }
    if (this.alertSubscribedChannel.length > 0 && this.alertChannelCallback !== null) {
      MessageBusService.getInstance().unsubscribe(this.alertSubscribedChannel, this.alertChannelCallback);
    }
    this.subscribedChannel = '';
    this.channelCallback = null;
    this.alertSubscribedChannel = '';
    this.alertChannelCallback = null;
    this.startedUserId = 0;
  }

  private applyUserState(user: User | null, notify: boolean): void {
    const nextUserId: number = user !== null ? Math.max(0, user.id) : 0;
    const nextAllUnread: number = user !== null ? Math.max(0, user.allUnreadNotificationsCount) : 0;
    const nextUnread: number = user !== null ? Math.max(0, user.unreadNotifications) : 0;
    const nextHighPriority: number = user !== null ? Math.max(0, user.unreadHighPriorityNotifications) : 0;
    const nextChannelPosition: number = user !== null ? Math.max(0, user.notificationChannelPosition) : 0;

    const changed: boolean = this.state.userId !== nextUserId
      || this.state.allUnread !== nextAllUnread
      || this.state.unread !== nextUnread
      || this.state.highPriority !== nextHighPriority
      || this.state.channelPosition !== nextChannelPosition;
    if (!changed) {
      return;
    }

    this.state.userId = nextUserId;
    this.state.allUnread = nextAllUnread;
    this.state.unread = nextUnread;
    this.state.highPriority = nextHighPriority;
    this.state.channelPosition = nextChannelPosition;
    if (notify) {
      this.notifyListeners();
    }
  }

  private buildPreviewCounts(notifications: DiscourseNotification[]): NotificationPreviewCounts {
    const counts: NotificationPreviewCounts = new NotificationPreviewCounts();
    for (let i = 0; i < notifications.length; i++) {
      const notification: DiscourseNotification = notifications[i];
      if (notification.read) {
        continue;
      }
      counts.allUnread += 1;
      if (notification.highPriority) {
        counts.highPriority += 1;
      }
    }
    return counts;
  }

  private applyPreviewCounts(
    currentUser: User,
    counts: NotificationPreviewCounts,
    seenNotificationId: number,
    preferHigher: boolean
  ): boolean {
    const nextAllUnread: number = preferHigher
      ? Math.max(currentUser.allUnreadNotificationsCount, counts.allUnread)
      : Math.max(0, counts.allUnread);
    const nextUnread: number = preferHigher
      ? Math.max(currentUser.unreadNotifications, counts.allUnread)
      : Math.max(0, counts.allUnread);
    const nextHighPriority: number = preferHigher
      ? Math.max(currentUser.unreadHighPriorityNotifications, counts.highPriority)
      : Math.max(0, counts.highPriority);
    const nextSeenNotificationId: number = seenNotificationId > 0
      ? Math.max(currentUser.seenNotificationId, seenNotificationId)
      : currentUser.seenNotificationId;

    let changed: boolean = false;
    if (currentUser.allUnreadNotificationsCount !== nextAllUnread) {
      currentUser.allUnreadNotificationsCount = nextAllUnread;
      changed = true;
    }
    if (currentUser.unreadNotifications !== nextUnread) {
      currentUser.unreadNotifications = nextUnread;
      changed = true;
    }
    if (currentUser.unreadHighPriorityNotifications !== nextHighPriority) {
      currentUser.unreadHighPriorityNotifications = nextHighPriority;
      changed = true;
    }
    if (currentUser.seenNotificationId !== nextSeenNotificationId) {
      currentUser.seenNotificationId = nextSeenNotificationId;
      changed = true;
    }
    return changed;
  }

  private async hydrateUnreadCountFromNotifications(currentUser: User | null): Promise<void> {
    if (currentUser === null || currentUser.id <= 0) {
      return;
    }
    if (Math.max(
      currentUser.allUnreadNotificationsCount,
      currentUser.unreadNotifications,
      currentUser.unreadHighPriorityNotifications
    ) > 0) {
      return;
    }

    try {
      const response = await ApiClient.getInstance().getNotifications(0, 40);
      const counts: NotificationPreviewCounts = this.buildPreviewCounts(response.notifications);
      if (!this.applyPreviewCounts(currentUser, counts, response.seenNotificationId, true)) {
        return;
      }
      AuthService.getInstance().setCurrentUser(currentUser, true);
      ApiClient.getInstance().setCachedCurrentUser(currentUser);
      this.applyUserState(currentUser, true);
      hilog.info(
        0x0000,
        TAG,
        'Recovered unread count from notification preview all=%{public}d high=%{public}d',
        currentUser.allUnreadNotificationsCount,
        currentUser.unreadHighPriorityNotifications
      );
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Recover unread count from notification preview failed: %{public}s', ApiClient.formatError(err));
    }
  }

  private async startInternal(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    const api: ApiClient = ApiClient.getInstance();
    await auth.init();

    if (!auth.getIsLoggedIn()) {
      this.resetState();
      this.stop();
      return;
    }

    let currentUser: User | null = auth.getCurrentUser();
    this.applyUserState(currentUser, false);

    try {
      api.invalidateCurrentUserCache();
      const latestUser: User | null = await api.getCurrentUser();
      if (latestUser !== null) {
        const shouldNotify: boolean = this.shouldNotifyCurrentUserUpdate(currentUser, latestUser);
        currentUser = latestUser;
        auth.setCurrentUser(latestUser, shouldNotify);
        api.setCachedCurrentUser(latestUser);
        this.applyUserState(latestUser, true);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Refresh current user before subscribe failed: %{public}s', ApiClient.formatError(err));
    }

    await this.hydrateUnreadCountFromNotifications(currentUser);

    if (currentUser === null || currentUser.id <= 0) {
      this.resetState();
      this.stop();
      return;
    }

    const nextChannel: string = `/notification/${currentUser.id}`;
    const nextAlertChannel: string = `/notification-alert/${currentUser.id}`;
    if (this.startedUserId === currentUser.id
      && this.subscribedChannel === nextChannel
      && this.alertSubscribedChannel === nextAlertChannel
      && this.channelCallback !== null
      && this.alertChannelCallback !== null) {
      return;
    }

    this.stop();

    try {
      await PreloadedDataService.getInstance().ensureConfigLoaded(true);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Ensure notification bus config failed: %{public}s', ApiClient.formatError(err));
    }

    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const bus: MessageBusService = MessageBusService.getInstance();
    bus.configure(preloaded.getLongPollingBaseUrl(), preloaded.getSharedSessionKey());

    const initialMessageId: number = currentUser.notificationChannelPosition;
    const expectedUserId: number = currentUser.id;
    this.channelCallback = (message: MessageBusMessage) => {
      this.handleChannelMessage(expectedUserId, message);
    };
    this.alertChannelCallback = (message: MessageBusMessage) => {
      this.handleAlertChannelMessage(expectedUserId, message);
    };
    this.subscribedChannel = nextChannel;
    this.alertSubscribedChannel = nextAlertChannel;
    this.startedUserId = expectedUserId;
    bus.subscribeWithMessageId(nextChannel, this.channelCallback, initialMessageId);
    bus.subscribeWithMessageId(nextAlertChannel, this.alertChannelCallback, -1);
    hilog.info(0x0000, TAG, 'Subscribed notification channel=%{public}s messageId=%{public}d', nextChannel, initialMessageId);
    hilog.info(0x0000, TAG, 'Subscribed notification alert channel=%{public}s', nextAlertChannel);
  }

  private readOptionalCount(data: Record<string, Object>, key: string): number | null {
    const value: Object | undefined = data[key];
    if (value === undefined || value === null) {
      return null;
    }
    const parsed: number = Number(value.toString());
    if (isNaN(parsed)) {
      return null;
    }
    return Math.max(0, Math.round(parsed));
  }

  private handleChannelMessage(expectedUserId: number, message: MessageBusMessage): void {
    if (message.channel !== this.subscribedChannel) {
      return;
    }
    if (message.data === null || message.data === undefined || typeof message.data !== 'object') {
      return;
    }

    const auth: AuthService = AuthService.getInstance();
    const currentUser: User | null = auth.getCurrentUser();
    if (currentUser === null || currentUser.id !== expectedUserId) {
      return;
    }

    const data: Record<string, Object> = message.data as Record<string, Object>;
    const allUnread: number | null = this.readOptionalCount(data, 'all_unread_notifications_count');
    const unread: number | null = this.readOptionalCount(data, 'unread_notifications');
    const highPriority: number | null = this.readOptionalCount(data, 'unread_high_priority_notifications');

    let changed: boolean = false;
    if (allUnread !== null && currentUser.allUnreadNotificationsCount !== allUnread) {
      currentUser.allUnreadNotificationsCount = allUnread;
      changed = true;
    }
    if (unread !== null && currentUser.unreadNotifications !== unread) {
      currentUser.unreadNotifications = unread;
      changed = true;
    }
    if (highPriority !== null && currentUser.unreadHighPriorityNotifications !== highPriority) {
      currentUser.unreadHighPriorityNotifications = highPriority;
      changed = true;
    }
    if (message.messageId > currentUser.notificationChannelPosition) {
      currentUser.notificationChannelPosition = message.messageId;
      changed = true;
    }

    if (!changed) {
      return;
    }

    auth.setCurrentUser(currentUser, true);
    ApiClient.getInstance().setCachedCurrentUser(currentUser);
    this.applyUserState(currentUser, true);
    hilog.info(
      0x0000,
      TAG,
      'Notification count updated all=%{public}d unread=%{public}d high=%{public}d',
      currentUser.allUnreadNotificationsCount,
      currentUser.unreadNotifications,
      currentUser.unreadHighPriorityNotifications
    );
  }

  private getAlertFallbackTitle(notificationType: number | null): string {
    if (notificationType === null) {
      return '新通知';
    }
    if (notificationType === 5) {
      return '有人回复了你';
    }
    if (notificationType === 6) {
      return '有人提到了你';
    }
    if (notificationType === 7) {
      return '有人引用了你';
    }
    if (notificationType === 15) {
      return '有人赞了你';
    }
    return '新通知';
  }

  private handleAlertChannelMessage(expectedUserId: number, message: MessageBusMessage): void {
    if (message.channel !== this.alertSubscribedChannel) {
      return;
    }
    const authUser: User | null = AuthService.getInstance().getCurrentUser();
    if (authUser === null || authUser.id !== expectedUserId) {
      return;
    }
    if (message.data === null || message.data === undefined || typeof message.data !== 'object') {
      return;
    }

    const data: Record<string, Object> = message.data as Record<string, Object>;
    const topicTitle: string = data['topic_title'] !== undefined && data['topic_title'] !== null
      ? data['topic_title'].toString()
      : '';
    const excerpt: string = data['excerpt'] !== undefined && data['excerpt'] !== null
      ? data['excerpt'].toString()
      : '';
    const username: string = data['username'] !== undefined && data['username'] !== null
      ? data['username'].toString()
      : '';
    const notificationType: number | null = data['notification_type'] !== undefined && data['notification_type'] !== null
      ? Number(data['notification_type'].toString())
      : null;

    let title: string = topicTitle.trim();
    if (title.length === 0) {
      title = this.getAlertFallbackTitle(notificationType);
    }

    let body: string = excerpt.trim();
    if (body.length === 0 && username.trim().length > 0) {
      body = username.trim();
    }
    if (body.length === 0) {
      body = '点击查看最新动态';
    }

    LocalNotificationService.getInstance()
      .show(title, body, message.messageId > 0 ? message.messageId : 0)
      .catch((err: Object) => {
        hilog.warn(0x0000, TAG, 'Show system notification failed: %{public}s', JSON.stringify(err));
      });
  }
}
